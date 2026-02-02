// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Accumulator} from "../src/Accumulator.sol";
import {Call, JobStatus} from "../src/types/Structs.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockSwap {
    function swap(address token, uint256 amount) external {
        MockERC20(token).mint(msg.sender, amount);
    }

    function fail() external pure {
        revert("swap failed");
    }
}

contract MockMessenger {
    function deliver(Accumulator acc, uint256 fromChain, MockERC20 token, uint256 amount, bytes calldata message)
        external
    {
        require(token.transfer(address(acc), amount), "transfer");
        acc.handleMessage(fromChain, amount, message);
    }
}

contract AccumulatorTest is Test {
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockSwap swap;
    MockMessenger messenger;
    Accumulator acc;
    address treasury = address(0xBEEF);

    function setUp() public {
        tokenIn = new MockERC20("In", "IN");
        tokenOut = new MockERC20("Out", "OUT");
        swap = new MockSwap();
        messenger = new MockMessenger();
        acc = new Accumulator(address(this), address(messenger), treasury);
    }

    function _message(
        address inputToken,
        address outputToken,
        address recipient,
        uint256 minInput,
        uint256 minOutput,
        Call[] memory calls,
        uint256 nonce
    ) internal pure returns (bytes memory) {
        return abi.encode(inputToken, outputToken, recipient, minInput, minOutput, calls, nonce);
    }

    function _intentHash(
        address inputToken,
        address outputToken,
        address recipient,
        uint256 minInput,
        uint256 minOutput,
        Call[] memory calls,
        uint256 nonce
    ) internal view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(address(this), inputToken, outputToken, recipient, minInput, minOutput, calls)
        );
        uint256 salt = (nonce << 60) | block.chainid;
        bytes32 result;
        assembly ("memory-safe") {
            mstore(0x00, salt)
            mstore(0x20, inner)
            result := keccak256(0x00, 0x40)
        }
        return result;
    }

    function test_messengerOnly() public {
        Call[] memory calls = new Call[](0);
        bytes memory msgPayload =
            _message(address(tokenIn), address(tokenIn), address(this), 1 ether, 1 ether, calls, 1);

        vm.expectRevert(abi.encodeWithSelector(Accumulator.UnrecognizedCaller.selector, address(this)));
        acc.handleMessage(1, 1 ether, msgPayload);
    }

    function test_accumulatesTracksStatusAndChains() public {
        Call[] memory calls = new Call[](0);
        bytes memory msgPayload =
            _message(address(tokenIn), address(tokenIn), address(this), 3 ether, 3 ether, calls, 11);
        bytes32 hash = _intentHash(address(tokenIn), address(tokenIn), address(this), 3 ether, 3 ether, calls, 11);

        tokenIn.mint(address(messenger), 3 ether);
        messenger.deliver(acc, 100, tokenIn, 1 ether, msgPayload);
        messenger.deliver(acc, 200, tokenIn, 2 ether, msgPayload);

        (uint256 received,, JobStatus status, address inputToken) = acc.jobs(hash);
        assertEq(received, 3 ether);
        assertEq(inputToken, address(tokenIn));
        assertEq(uint256(status), uint256(JobStatus.Accumulated));
    }

    function test_approveBeforeAccumulated_executesNoSwap() public {
        Call[] memory calls = new Call[](0);
        bytes memory msgPayload =
            _message(address(tokenIn), address(tokenIn), address(this), 10 ether, 10 ether, calls, 2);
        bytes32 hash = _intentHash(address(tokenIn), address(tokenIn), address(this), 10 ether, 10 ether, calls, 2);

        acc.approve(hash);
        tokenIn.mint(address(messenger), 10 ether);
        messenger.deliver(acc, 10, tokenIn, 10 ether, msgPayload);

        assertEq(tokenIn.balanceOf(address(this)), 10 ether);
    }

    function test_approvedBeforeAccumulated_waitsForMore() public {
        Call[] memory calls = new Call[](0);
        bytes memory msgPayload =
            _message(address(tokenIn), address(tokenIn), address(this), 5 ether, 5 ether, calls, 12);
        bytes32 hash = _intentHash(address(tokenIn), address(tokenIn), address(this), 5 ether, 5 ether, calls, 12);

        acc.approve(hash);
        tokenIn.mint(address(messenger), 2 ether);
        messenger.deliver(acc, 10, tokenIn, 2 ether, msgPayload);

        (uint256 received,, JobStatus status,) = acc.jobs(hash);
        assertEq(received, 2 ether);
        assertEq(uint256(status), uint256(JobStatus.Accumulating));
    }

    function test_approveAfterAccumulated_refunds() public {
        Call[] memory calls = new Call[](0);
        bytes memory msgPayload =
            _message(address(tokenIn), address(tokenIn), address(this), 5 ether, 5 ether, calls, 3);
        bytes32 hash = _intentHash(address(tokenIn), address(tokenIn), address(this), 5 ether, 5 ether, calls, 3);

        tokenIn.mint(address(messenger), 5 ether);
        messenger.deliver(acc, 10, tokenIn, 5 ether, msgPayload);

        acc.approve(hash);
        assertEq(tokenIn.balanceOf(address(this)), 5 ether);
    }

    function test_swapSuccess_paysRecipient() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(swap),
            value: 0,
            data: abi.encodeWithSignature("swap(address,uint256)", address(tokenOut), 7 ether)
        });

        bytes memory msgPayload =
            _message(address(tokenIn), address(tokenOut), address(this), 7 ether, 7 ether, calls, 4);
        bytes32 hash = _intentHash(address(tokenIn), address(tokenOut), address(this), 7 ether, 7 ether, calls, 4);

        acc.approve(hash);
        tokenIn.mint(address(messenger), 7 ether);
        messenger.deliver(acc, 10, tokenIn, 7 ether, msgPayload);

        assertEq(tokenOut.balanceOf(address(this)), 7 ether);
    }

    function test_swapOutAboveMinOutput_capsTransfer() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(swap),
            value: 0,
            data: abi.encodeWithSignature("swap(address,uint256)", address(tokenOut), 10 ether)
        });

        bytes memory msgPayload =
            _message(address(tokenIn), address(tokenOut), address(this), 5 ether, 6 ether, calls, 13);
        bytes32 hash = _intentHash(address(tokenIn), address(tokenOut), address(this), 5 ether, 6 ether, calls, 13);

        acc.approve(hash);
        tokenIn.mint(address(messenger), 5 ether);
        messenger.deliver(acc, 10, tokenIn, 5 ether, msgPayload);

        assertEq(tokenOut.balanceOf(address(this)), 6 ether);
    }

    function test_swapOutBelowMinOutput_sendsActual() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(swap),
            value: 0,
            data: abi.encodeWithSignature("swap(address,uint256)", address(tokenOut), 2 ether)
        });

        bytes memory msgPayload =
            _message(address(tokenIn), address(tokenOut), address(this), 5 ether, 3 ether, calls, 16);
        bytes32 hash = _intentHash(address(tokenIn), address(tokenOut), address(this), 5 ether, 3 ether, calls, 16);

        acc.approve(hash);
        tokenIn.mint(address(messenger), 5 ether);
        messenger.deliver(acc, 10, tokenIn, 5 ether, msgPayload);

        assertEq(tokenOut.balanceOf(address(this)), 2 ether);
    }

    function test_swapFailure_refunds() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(swap), value: 0, data: abi.encodeWithSignature("fail()")});

        bytes memory msgPayload =
            _message(address(tokenIn), address(tokenOut), address(this), 4 ether, 4 ether, calls, 5);
        bytes32 hash = _intentHash(address(tokenIn), address(tokenOut), address(this), 4 ether, 4 ether, calls, 5);

        acc.approve(hash);
        tokenIn.mint(address(messenger), 4 ether);
        messenger.deliver(acc, 10, tokenIn, 4 ether, msgPayload);

        assertEq(tokenIn.balanceOf(address(this)), 4 ether);
    }

    function test_outputTokenMismatch_noSwap_refunds() public {
        Call[] memory calls = new Call[](0);
        bytes memory msgPayload =
            _message(address(tokenIn), address(tokenOut), address(this), 2 ether, 2 ether, calls, 6);
        bytes32 hash = _intentHash(address(tokenIn), address(tokenOut), address(this), 2 ether, 2 ether, calls, 6);

        acc.approve(hash);
        tokenIn.mint(address(messenger), 2 ether);
        messenger.deliver(acc, 10, tokenIn, 2 ether, msgPayload);

        assertEq(tokenIn.balanceOf(address(this)), 2 ether);
    }

    function test_duplicateFills_capAtMinInput() public {
        Call[] memory calls = new Call[](0);
        bytes memory msgPayload =
            _message(address(tokenIn), address(tokenIn), address(this), 3 ether, 3 ether, calls, 7);
        bytes32 hash = _intentHash(address(tokenIn), address(tokenIn), address(this), 3 ether, 3 ether, calls, 7);

        acc.approve(hash);
        tokenIn.mint(address(messenger), 5 ether);
        messenger.deliver(acc, 10, tokenIn, 2 ether, msgPayload);
        messenger.deliver(acc, 11, tokenIn, 3 ether, msgPayload);

        assertEq(tokenIn.balanceOf(address(this)), 3 ether);
    }

    function test_ignoreWrongInputToken() public {
        MockERC20 other = new MockERC20("Other", "O");
        Call[] memory calls = new Call[](0);
        bytes memory msgPayload =
            _message(address(tokenIn), address(tokenIn), address(this), 1 ether, 1 ether, calls, 8);
        bytes32 hash = _intentHash(address(tokenIn), address(tokenIn), address(this), 1 ether, 1 ether, calls, 8);

        acc.approve(hash);

        tokenIn.mint(address(messenger), 1 ether);
        messenger.deliver(acc, 10, tokenIn, 1 ether, msgPayload);

        // Same intent hash but wrong token should be ignored
        other.mint(address(messenger), 1 ether);
        messenger.deliver(acc, 11, other, 1 ether, msgPayload);

        assertEq(tokenIn.balanceOf(address(this)), 1 ether);
        assertEq(other.balanceOf(address(this)), 0);
        assertEq(other.balanceOf(address(acc)), 1 ether);
    }

    function test_ignoreAfterRefunded() public {
        Call[] memory calls = new Call[](0);
        bytes memory msgPayload =
            _message(address(tokenIn), address(tokenIn), address(this), 1 ether, 1 ether, calls, 14);
        bytes32 hash = _intentHash(address(tokenIn), address(tokenIn), address(this), 1 ether, 1 ether, calls, 14);

        tokenIn.mint(address(messenger), 1 ether);
        messenger.deliver(acc, 1, tokenIn, 1 ether, msgPayload);

        acc.approve(hash);
        assertEq(tokenIn.balanceOf(address(this)), 1 ether);

        tokenIn.mint(address(messenger), 1 ether);
        messenger.deliver(acc, 2, tokenIn, 1 ether, msgPayload);

        (uint256 received,, JobStatus status,) = acc.jobs(hash);
        assertEq(uint256(status), uint256(JobStatus.Refunded));
        assertEq(received, 1 ether);
    }

    function test_approveAfterExecuted_reverts() public {
        Call[] memory calls = new Call[](0);
        bytes memory msgPayload =
            _message(address(tokenIn), address(tokenIn), address(this), 1 ether, 1 ether, calls, 15);
        bytes32 hash = _intentHash(address(tokenIn), address(tokenIn), address(this), 1 ether, 1 ether, calls, 15);

        acc.approve(hash);
        tokenIn.mint(address(messenger), 1 ether);
        messenger.deliver(acc, 10, tokenIn, 1 ether, msgPayload);

        vm.expectRevert(Accumulator.AlreadyExecuted.selector);
        acc.approve(hash);
    }

    function test_approveTwice_noRevert() public {
        Call[] memory calls = new Call[](0);
        bytes32 hash = _intentHash(address(tokenIn), address(tokenIn), address(this), 1 ether, 1 ether, calls, 9);
        acc.approve(hash);
        acc.approve(hash);
    }

    function test_sweepMovesBalance() public {
        tokenIn.mint(address(acc), 1 ether);
        acc.sweep(address(tokenIn));
        assertEq(tokenIn.balanceOf(treasury), 1 ether);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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

    function deliverNative(Accumulator acc, uint256 fromChain, uint256 amount, bytes calldata message)
        external
        payable
    {
        (bool ok,) = address(acc).call{value: amount}("");
        require(ok, "eth transfer");
        acc.handleMessage(fromChain, amount, message);
    }

    receive() external payable {}
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

        (uint256 received,,, JobStatus status, address inputToken) = acc.jobs(hash);
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

        (uint256 received,,, JobStatus status,) = acc.jobs(hash);
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

        (uint256 received,,, JobStatus status,) = acc.jobs(hash);
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

    // ──────────────────────────────────────────────
    //  Native ETH tests
    // ──────────────────────────────────────────────

    address constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function test_native_accumulatesAndExecutes_noSwap() public {
        Call[] memory calls = new Call[](0);
        address recipient = address(0xCAFE);
        bytes memory msgPayload =
            _message(NATIVE, NATIVE, recipient, 2 ether, 2 ether, calls, 20);
        bytes32 hash = _intentHash(NATIVE, NATIVE, recipient, 2 ether, 2 ether, calls, 20);

        acc.approve(hash);

        vm.deal(address(messenger), 2 ether);
        messenger.deliverNative{value: 2 ether}(acc, 10, 2 ether, msgPayload);

        assertEq(recipient.balance, 2 ether);
    }

    function test_native_accumulatesMultipleFills() public {
        Call[] memory calls = new Call[](0);
        bytes memory msgPayload =
            _message(NATIVE, NATIVE, address(this), 3 ether, 3 ether, calls, 21);
        bytes32 hash = _intentHash(NATIVE, NATIVE, address(this), 3 ether, 3 ether, calls, 21);

        vm.deal(address(messenger), 3 ether);
        messenger.deliverNative{value: 1 ether}(acc, 100, 1 ether, msgPayload);
        messenger.deliverNative{value: 2 ether}(acc, 200, 2 ether, msgPayload);

        (uint256 received,,, JobStatus status, address inputToken) = acc.jobs(hash);
        assertEq(received, 3 ether);
        assertEq(inputToken, NATIVE);
        assertEq(uint256(status), uint256(JobStatus.Accumulated));
    }

    function test_native_lateApprovalRefunds() public {
        Call[] memory calls = new Call[](0);
        bytes memory msgPayload =
            _message(NATIVE, NATIVE, address(this), 1 ether, 1 ether, calls, 22);
        bytes32 hash = _intentHash(NATIVE, NATIVE, address(this), 1 ether, 1 ether, calls, 22);

        vm.deal(address(messenger), 1 ether);
        messenger.deliverNative{value: 1 ether}(acc, 10, 1 ether, msgPayload);

        uint256 balBefore = address(this).balance;
        acc.approve(hash);
        assertEq(address(this).balance - balBefore, 1 ether);
    }

    function test_native_swapToERC20() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(swap),
            value: 0,
            data: abi.encodeWithSignature("swap(address,uint256)", address(tokenOut), 5 ether)
        });

        bytes memory msgPayload =
            _message(NATIVE, address(tokenOut), address(this), 5 ether, 5 ether, calls, 23);
        bytes32 hash = _intentHash(NATIVE, address(tokenOut), address(this), 5 ether, 5 ether, calls, 23);

        acc.approve(hash);
        vm.deal(address(messenger), 5 ether);
        messenger.deliverNative{value: 5 ether}(acc, 10, 5 ether, msgPayload);

        assertEq(tokenOut.balanceOf(address(this)), 5 ether);
    }

    function test_native_swapFailureRefundsETH() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(swap), value: 0, data: abi.encodeWithSignature("fail()")});

        // owner() == address(this), so refund goes back here.
        // Use vm.deal on the accumulator directly and call via prank to avoid
        // the test contract's own ETH muddying the accounting.
        bytes memory msgPayload =
            _message(NATIVE, address(tokenOut), address(this), 3 ether, 3 ether, calls, 24);
        bytes32 hash = _intentHash(NATIVE, address(tokenOut), address(this), 3 ether, 3 ether, calls, 24);

        acc.approve(hash);

        // Simulate messenger delivering native ETH to the accumulator.
        vm.deal(address(acc), 3 ether);
        vm.prank(address(messenger));
        acc.handleMessage(10, 3 ether, msgPayload);

        // Swap failed → refund to owner (this contract). Accumulator should be drained.
        assertEq(address(acc).balance, 0);
    }

    function test_native_sweepETH() public {
        vm.deal(address(acc), 2 ether);
        acc.sweep(NATIVE);
        assertEq(treasury.balance, 2 ether);
    }

    receive() external payable {}
}

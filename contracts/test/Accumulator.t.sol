// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Accumulator} from "../src/Accumulator.sol";
import {Call, FillStatus} from "../src/types/Structs.sol";

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

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

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 current = allowance[from][msg.sender];
        require(current >= amount, "allowance");
        require(balanceOf[from] >= amount, "balance");
        allowance[from][msg.sender] = current - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockSpokePool {
    function deliver(Accumulator acc, MockERC20 token, uint256 amount, address relayer, bytes memory message) external {
        require(token.transfer(address(acc), amount), "transfer");
        acc.handleV3AcrossMessage(address(token), amount, relayer, message);
    }
}

contract MockSwap {
    function mintToCaller(address token, uint256 amount) external {
        MockERC20(token).mint(msg.sender, amount);
    }

    function noop() external {}

    function fail() external pure {
        revert("fail");
    }
}

contract AccumulatorTest is Test {
    bytes32 private constant ZERO_SALT = bytes32(0);

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockSwap swap;
    MockSpokePool spokePool;
    Accumulator acc;

    address recipient = address(0xCAFE);
    address relayer = address(0xFEED);

    function setUp() public {
        tokenIn = new MockERC20("In", "IN");
        tokenOut = new MockERC20("Out", "OUT");
        swap = new MockSwap();
        spokePool = new MockSpokePool();
        acc = new Accumulator(address(this));
        acc.initialize(address(spokePool));
    }

    event FillExecuted(
        bytes32 indexed fillId,
        address indexed recipient,
        address finalOutputToken,
        uint256 requestedOutput,
        uint256 actualOutput,
        uint256[] sourceChainIds
    );

    function test_access_spokePoolCanCall() public {
        bytes memory msgPayload = _message({
            salt: ZERO_SALT,
            fromChainId: 1,
            fillDeadline: uint32(block.timestamp + 1 hours),
            depositor: address(this),
            _recipient: recipient,
            sumOutput: 1 ether,
            finalMinOutput: 1 ether,
            finalOutputToken: address(tokenIn),
            calls: _emptyCalls()
        });

        tokenIn.mint(address(spokePool), 1 ether);
        spokePool.deliver(acc, tokenIn, 1 ether, relayer, msgPayload);

        assertEq(tokenIn.balanceOf(recipient), 1 ether);
    }

    function test_access_ownerCanCallDirectly() public {
        bytes memory msgPayload = _simpleMessage(address(tokenIn), 2 ether);

        tokenIn.mint(address(acc), 2 ether);
        acc.handleV3AcrossMessage(address(tokenIn), 2 ether, relayer, msgPayload);

        assertEq(tokenIn.balanceOf(recipient), 2 ether);
    }

    function test_access_randomCallerReverts() public {
        bytes memory msgPayload = _simpleMessage(address(tokenIn), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(Accumulator.UnrecognizedCaller.selector, address(0xDEAD)));
        vm.prank(address(0xDEAD));
        acc.handleV3AcrossMessage(address(tokenIn), 1 ether, relayer, msgPayload);
    }

    function test_invalidOriginatorReverts() public {
        bytes memory msgPayload = _message({
            salt: ZERO_SALT,
            fromChainId: 1,
            fillDeadline: uint32(block.timestamp + 1 hours),
            depositor: address(0xDEAD),
            _recipient: recipient,
            sumOutput: 1 ether,
            finalMinOutput: 1 ether,
            finalOutputToken: address(tokenIn),
            calls: _emptyCalls()
        });

        tokenIn.mint(address(spokePool), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(Accumulator.InvalidOriginator.selector, address(0xDEAD)));
        spokePool.deliver(acc, tokenIn, 1 ether, relayer, msgPayload);
    }

    function test_singleFill_directTransferExecutes() public {
        bytes memory msgPayload = _simpleMessage(address(tokenIn), 3 ether);

        tokenIn.mint(address(spokePool), 3 ether);
        spokePool.deliver(acc, tokenIn, 3 ether, relayer, msgPayload);

        assertEq(tokenIn.balanceOf(recipient), 3 ether);
        assertEq(acc.reservedByToken(address(tokenIn)), 0);
    }

    function test_multipleFills_accumulateThenExecute() public {
        bytes memory msgPayload = _simpleMessage(address(tokenIn), 5 ether);

        tokenIn.mint(address(spokePool), 5 ether);
        spokePool.deliver(acc, tokenIn, 2 ether, relayer, msgPayload);
        assertEq(tokenIn.balanceOf(recipient), 0);
        assertEq(acc.reservedByToken(address(tokenIn)), 2 ether);

        spokePool.deliver(acc, tokenIn, 3 ether, relayer, msgPayload);
        assertEq(tokenIn.balanceOf(recipient), 5 ether);
        assertEq(acc.reservedByToken(address(tokenIn)), 0);
    }

    function test_overfill_onlyCreditsUpToTargetAndSweepRecoversExcess() public {
        bytes memory msgPayload = _simpleMessage(address(tokenIn), 7 ether);

        tokenIn.mint(address(spokePool), 10 ether);
        spokePool.deliver(acc, tokenIn, 10 ether, relayer, msgPayload);

        assertEq(tokenIn.balanceOf(recipient), 7 ether);
        assertEq(tokenIn.balanceOf(address(this)), 3 ether);
        assertEq(tokenIn.balanceOf(address(acc)), 0);
    }

    function test_noDestCalls_finalOutputMustEqualInputToken() public {
        bytes memory msgPayload = _message({
            salt: ZERO_SALT,
            fromChainId: 1,
            fillDeadline: uint32(block.timestamp + 1 hours),
            depositor: address(this),
            _recipient: recipient,
            sumOutput: 5 ether,
            finalMinOutput: 5 ether,
            finalOutputToken: address(tokenOut),
            calls: _emptyCalls()
        });

        tokenIn.mint(address(spokePool), 5 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                Accumulator.InvalidFinalOutputTokenForDirectTransfer.selector, address(tokenIn), address(tokenOut)
            )
        );
        spokePool.deliver(acc, tokenIn, 5 ether, relayer, msgPayload);
    }

    function test_tokenMismatchIgnoredWithoutRevert() public {
        bytes memory msgPayload = _simpleMessage(address(tokenIn), 5 ether);

        tokenIn.mint(address(spokePool), 2 ether);
        spokePool.deliver(acc, tokenIn, 2 ether, relayer, msgPayload);

        tokenOut.mint(address(spokePool), 2 ether);
        spokePool.deliver(acc, tokenOut, 2 ether, relayer, msgPayload);

        bytes32 fillId = _fillId(
            ZERO_SALT,
            uint32(block.timestamp + 1 hours),
            address(this),
            recipient,
            5 ether,
            5 ether,
            address(tokenIn),
            _emptyCalls()
        );
        (uint256 received,,,,,,, FillStatus status) = acc.fills(fillId);
        assertEq(received, 2 ether);
        assertEq(uint8(status), uint8(FillStatus.Accumulating));
        assertEq(tokenOut.balanceOf(address(acc)), 0);
        assertEq(tokenOut.balanceOf(address(this)), 2 ether);
    }

    function test_staleOnArrival_marksStaleAndRefunds() public {
        uint32 pastDeadline = uint32(block.timestamp - 1);
        bytes memory msgPayload = _message({
            salt: ZERO_SALT,
            fromChainId: 1,
            fillDeadline: pastDeadline,
            depositor: address(this),
            _recipient: recipient,
            sumOutput: 5 ether,
            finalMinOutput: 5 ether,
            finalOutputToken: address(tokenIn),
            calls: _emptyCalls()
        });

        tokenIn.mint(address(spokePool), 5 ether);
        spokePool.deliver(acc, tokenIn, 5 ether, relayer, msgPayload);

        assertEq(tokenIn.balanceOf(address(this)), 5 ether);
        bytes32 fillId = _fillId(
            ZERO_SALT,
            pastDeadline,
            address(this),
            recipient,
            5 ether,
            5 ether,
            address(tokenIn),
            _emptyCalls()
        );
        (,,,,,,, FillStatus status) = acc.fills(fillId);
        assertEq(uint8(status), uint8(FillStatus.Stale));
    }

    function test_lateArrivalAfterStale_isAutoRefunded() public {
        uint32 pastDeadline = uint32(block.timestamp - 1);
        bytes memory msgPayload = _message({
            salt: ZERO_SALT,
            fromChainId: 1,
            fillDeadline: pastDeadline,
            depositor: address(this),
            _recipient: recipient,
            sumOutput: 5 ether,
            finalMinOutput: 5 ether,
            finalOutputToken: address(tokenIn),
            calls: _emptyCalls()
        });

        tokenIn.mint(address(spokePool), 8 ether);
        spokePool.deliver(acc, tokenIn, 5 ether, relayer, msgPayload);
        spokePool.deliver(acc, tokenIn, 3 ether, relayer, msgPayload);

        assertEq(tokenIn.balanceOf(address(this)), 8 ether);
        assertEq(tokenIn.balanceOf(address(acc)), 0);
    }

    function test_postDeadlineTokenMismatchStillMarksStaleAndRefunds() public {
        uint32 deadline = uint32(block.timestamp + 10);
        bytes memory msgPayload = _message({
            salt: ZERO_SALT,
            fromChainId: 1,
            fillDeadline: deadline,
            depositor: address(this),
            _recipient: recipient,
            sumOutput: 5 ether,
            finalMinOutput: 5 ether,
            finalOutputToken: address(tokenIn),
            calls: _emptyCalls()
        });

        tokenIn.mint(address(spokePool), 2 ether);
        spokePool.deliver(acc, tokenIn, 2 ether, relayer, msgPayload);
        assertEq(acc.reservedByToken(address(tokenIn)), 2 ether);

        vm.warp(deadline + 1);

        tokenOut.mint(address(spokePool), 1 ether);
        spokePool.deliver(acc, tokenOut, 1 ether, relayer, msgPayload);

        bytes32 fillId = _fillId(
            ZERO_SALT,
            deadline,
            address(this),
            recipient,
            5 ether,
            5 ether,
            address(tokenIn),
            _emptyCalls()
        );
        (uint256 received,,,,,,, FillStatus status) = acc.fills(fillId);
        assertEq(received, 0);
        assertEq(uint8(status), uint8(FillStatus.Stale));
        assertEq(acc.reservedByToken(address(tokenIn)), 0);

        // Both expected-token accumulated funds and mismatched late-arrival funds are refunded.
        assertEq(tokenIn.balanceOf(address(this)), 2 ether);
        assertEq(tokenOut.balanceOf(address(this)), 1 ether);
        assertEq(tokenIn.balanceOf(address(acc)), 0);
        assertEq(tokenOut.balanceOf(address(acc)), 0);
    }

    function test_sweep_onlyTransfersAvailableNotReserved() public {
        bytes memory msgPayload = _simpleMessage(address(tokenIn), 10 ether);

        tokenIn.mint(address(spokePool), 6 ether);
        spokePool.deliver(acc, tokenIn, 6 ether, relayer, msgPayload);

        tokenIn.mint(address(acc), 4 ether);
        acc.sweep(address(tokenIn));

        assertEq(tokenIn.balanceOf(address(this)), 4 ether);
        assertEq(tokenIn.balanceOf(address(acc)), 6 ether);
        assertEq(acc.reservedByToken(address(tokenIn)), 6 ether);
    }

    function test_sourceChainIdsAreUnique() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        bytes memory msgPayload = _message({
            salt: ZERO_SALT,
            fromChainId: 42,
            fillDeadline: deadline,
            depositor: address(this),
            _recipient: recipient,
            sumOutput: 5 ether,
            finalMinOutput: 5 ether,
            finalOutputToken: address(tokenIn),
            calls: _emptyCalls()
        });

        tokenIn.mint(address(spokePool), 5 ether);
        spokePool.deliver(acc, tokenIn, 2 ether, relayer, msgPayload);

        uint256[] memory expectedChains = new uint256[](1);
        expectedChains[0] = 42;
        bytes32 fillId = _fillId(
            ZERO_SALT,
            deadline,
            address(this),
            recipient,
            5 ether,
            5 ether,
            address(tokenIn),
            _emptyCalls()
        );

        vm.expectEmit(true, true, false, true);
        emit FillExecuted(fillId, recipient, address(tokenIn), 5 ether, 5 ether, expectedChains);
        spokePool.deliver(acc, tokenIn, 3 ether, relayer, msgPayload);
    }

    function test_differentSaltsCreateDistinctFillIds() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        bytes32 saltA = keccak256("A");
        bytes32 saltB = keccak256("B");

        bytes memory msgA = _message({
            salt: saltA,
            fromChainId: 1,
            fillDeadline: deadline,
            depositor: address(this),
            _recipient: recipient,
            sumOutput: 1 ether,
            finalMinOutput: 1 ether,
            finalOutputToken: address(tokenIn),
            calls: _emptyCalls()
        });
        bytes memory msgB = _message({
            salt: saltB,
            fromChainId: 1,
            fillDeadline: deadline,
            depositor: address(this),
            _recipient: recipient,
            sumOutput: 1 ether,
            finalMinOutput: 1 ether,
            finalOutputToken: address(tokenIn),
            calls: _emptyCalls()
        });

        tokenIn.mint(address(spokePool), 2 ether);
        spokePool.deliver(acc, tokenIn, 1 ether, relayer, msgA);
        spokePool.deliver(acc, tokenIn, 1 ether, relayer, msgB);

        bytes32 fillIdA = _fillId(
            saltA,
            deadline,
            address(this),
            recipient,
            1 ether,
            1 ether,
            address(tokenIn),
            _emptyCalls()
        );
        bytes32 fillIdB = _fillId(
            saltB,
            deadline,
            address(this),
            recipient,
            1 ether,
            1 ether,
            address(tokenIn),
            _emptyCalls()
        );

        assertTrue(fillIdA != fillIdB);

        (,,,,,,, FillStatus statusA) = acc.fills(fillIdA);
        (,,,,,,, FillStatus statusB) = acc.fills(fillIdB);
        assertEq(uint8(statusA), uint8(FillStatus.Executed));
        assertEq(uint8(statusB), uint8(FillStatus.Executed));
    }

    function test_setSpokePool_onlyOwner() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        acc.setSpokePool(address(0x1234));
    }

    function test_perFillOutputIsolation_doesNotSpendOtherReservations() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(swap), value: 0, data: abi.encodeCall(MockSwap.noop, ())});

        // Fill B: remains active with 5 reserved
        bytes memory msgB = _message({
            salt: keccak256("B"),
            fromChainId: 1,
            fillDeadline: deadline,
            depositor: address(this),
            _recipient: address(0xBBBB),
            sumOutput: 10 ether,
            finalMinOutput: 10 ether,
            finalOutputToken: address(tokenIn),
            calls: calls
        });

        // Fill A: executes with finalMinOutput > attributable output
        bytes memory msgA = _message({
            salt: keccak256("A"),
            fromChainId: 1,
            fillDeadline: deadline,
            depositor: address(this),
            _recipient: recipient,
            sumOutput: 5 ether,
            finalMinOutput: 10 ether,
            finalOutputToken: address(tokenIn),
            calls: calls
        });

        tokenIn.mint(address(spokePool), 10 ether);
        spokePool.deliver(acc, tokenIn, 5 ether, relayer, msgB);
        spokePool.deliver(acc, tokenIn, 5 ether, relayer, msgA);

        // A should only send its attributable 5, not consume B's reserved 5.
        assertEq(tokenIn.balanceOf(recipient), 5 ether);
        assertEq(tokenIn.balanceOf(address(acc)), 5 ether);
        assertEq(acc.reservedByToken(address(tokenIn)), 5 ether);
    }

    function test_destCalls_outputTokenUsesProducedAmountAndCap() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(swap), value: 0, data: abi.encodeCall(MockSwap.mintToCaller, (address(tokenOut), 8 ether))
        });

        bytes memory msgPayload = _message({
            salt: ZERO_SALT,
            fromChainId: 1,
            fillDeadline: uint32(block.timestamp + 1 hours),
            depositor: address(this),
            _recipient: recipient,
            sumOutput: 5 ether,
            finalMinOutput: 6 ether,
            finalOutputToken: address(tokenOut),
            calls: calls
        });

        tokenIn.mint(address(spokePool), 5 ether);
        spokePool.deliver(acc, tokenIn, 5 ether, relayer, msgPayload);

        // Produced 8 OUT, capped by finalMinOutput 6.
        assertEq(tokenOut.balanceOf(recipient), 6 ether);
        assertEq(tokenOut.balanceOf(address(this)), 2 ether);
        assertEq(tokenOut.balanceOf(address(acc)), 0);
    }

    function test_destCallRevertBubblesUp() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(swap), value: 0, data: abi.encodeCall(MockSwap.fail, ())});

        bytes memory msgPayload = _message({
            salt: ZERO_SALT,
            fromChainId: 1,
            fillDeadline: uint32(block.timestamp + 1 hours),
            depositor: address(this),
            _recipient: recipient,
            sumOutput: 5 ether,
            finalMinOutput: 5 ether,
            finalOutputToken: address(tokenIn),
            calls: calls
        });

        tokenIn.mint(address(spokePool), 5 ether);
        vm.expectRevert(bytes("fail"));
        spokePool.deliver(acc, tokenIn, 5 ether, relayer, msgPayload);
    }

    // ───────────────────────── helpers ─────────────────────────

    function _emptyCalls() internal pure returns (Call[] memory calls) {
        calls = new Call[](0);
    }

    function _simpleMessage(address finalOutputToken, uint256 amount) internal view returns (bytes memory) {
        return _message({
            salt: ZERO_SALT,
            fromChainId: block.chainid,
            fillDeadline: uint32(block.timestamp + 1 hours),
            depositor: address(this),
            _recipient: recipient,
            sumOutput: amount,
            finalMinOutput: amount,
            finalOutputToken: finalOutputToken,
            calls: _emptyCalls()
        });
    }

    function _message(
        bytes32 salt,
        uint256 fromChainId,
        uint32 fillDeadline,
        address depositor,
        address _recipient,
        uint256 sumOutput,
        uint256 finalMinOutput,
        address finalOutputToken,
        Call[] memory calls
    ) internal pure returns (bytes memory) {
        bytes memory destCallsEncoded = calls.length > 0 ? abi.encode(calls) : bytes("");
        return abi.encode(
            salt,
            fromChainId,
            fillDeadline,
            depositor,
            _recipient,
            sumOutput,
            finalMinOutput,
            finalOutputToken,
            destCallsEncoded
        );
    }

    function _fillId(
        bytes32 salt,
        uint32 fillDeadline,
        address depositor,
        address _recipient,
        uint256 sumOutput,
        uint256 finalMinOutput,
        address finalOutputToken,
        Call[] memory calls
    ) internal pure returns (bytes32) {
        bytes memory destCallsEncoded = calls.length > 0 ? abi.encode(calls) : bytes("");
        return keccak256(
            abi.encode(
                salt,
                depositor,
                fillDeadline,
                _recipient,
                sumOutput,
                finalMinOutput,
                finalOutputToken,
                destCallsEncoded
            )
        );
    }

    receive() external payable {}
}

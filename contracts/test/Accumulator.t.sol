// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Accumulator} from "../src/Accumulator.sol";
import {IMerkleVerifier} from "../src/interfaces/IMerkleVerifier.sol";
import {Call, ExecutionParams, FillStatus} from "../src/types/Structs.sol";

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

/// @dev Mock owner that always returns valid for verifyMerkleRoot.
contract MockOwner is IMerkleVerifier {
    function verifyMerkleRoot(bytes32, bytes32[] calldata, bytes calldata) external pure override returns (bytes4) {
        return IMerkleVerifier.verifyMerkleRoot.selector;
    }
}

/// @dev Mock owner that always returns invalid for verifyMerkleRoot.
contract MockOwnerInvalid is IMerkleVerifier {
    function verifyMerkleRoot(bytes32, bytes32[] calldata, bytes calldata) external pure override returns (bytes4) {
        return bytes4(0xffffffff);
    }
}

contract AccumulatorTest is Test {
    bytes32 private constant ZERO_SALT = bytes32(0);

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockSwap swap;
    MockSpokePool spokePool;
    MockOwner mockOwner;
    Accumulator acc;

    address recipient = address(0xCAFE);
    address relayer = address(0xFEED);
    address destinationCaller;

    function setUp() public {
        tokenIn = new MockERC20("In", "IN");
        tokenOut = new MockERC20("Out", "OUT");
        swap = new MockSwap();
        spokePool = new MockSpokePool();
        mockOwner = new MockOwner();
        acc = new Accumulator(address(mockOwner));
        acc.initialize(address(spokePool));
        destinationCaller = address(this);
    }

    event FillAccumulated(
        bytes32 indexed fillId, address indexed inputToken, uint256 amount, uint256 totalReceived, uint256 sumOutput
    );

    event FillReady(bytes32 indexed fillId, uint256 totalReceived, uint256 sumOutput);

    event FillExecuted(
        bytes32 indexed fillId,
        address indexed recipient,
        address finalOutputToken,
        uint256 requestedOutput,
        uint256 actualOutput,
        uint256[] sourceChainIds
    );

    // ═══════════════════════════════════════════════════════════════════════════
    //  Step 1: Accumulate tests
    // ═══════════════════════════════════════════════════════════════════════════

    function test_access_spokePoolCanCall() public {
        bytes memory msg_ = _accMessage(ZERO_SALT, 1, uint32(block.timestamp + 1 hours), address(mockOwner), 1 ether);

        tokenIn.mint(address(spokePool), 1 ether);
        spokePool.deliver(acc, tokenIn, 1 ether, relayer, msg_);

        // Tokens accumulate, no execution
        assertEq(acc.reservedByToken(address(tokenIn)), 1 ether);
        assertEq(tokenIn.balanceOf(address(acc)), 1 ether);
    }

    function test_access_ownerCanCallDirectly() public {
        bytes memory msg_ =
            _accMessage(ZERO_SALT, block.chainid, uint32(block.timestamp + 1 hours), address(mockOwner), 2 ether);

        tokenIn.mint(address(acc), 2 ether);
        vm.prank(address(mockOwner));
        acc.handleV3AcrossMessage(address(tokenIn), 2 ether, relayer, msg_);

        assertEq(acc.reservedByToken(address(tokenIn)), 2 ether);
    }

    function test_access_randomCallerReverts() public {
        bytes memory msg_ = _accMessage(ZERO_SALT, 1, uint32(block.timestamp + 1 hours), address(mockOwner), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(Accumulator.UnrecognizedCaller.selector, address(0xDEAD)));
        vm.prank(address(0xDEAD));
        acc.handleV3AcrossMessage(address(tokenIn), 1 ether, relayer, msg_);
    }

    function test_invalidOriginatorReverts() public {
        bytes memory msg_ = _accMessage(ZERO_SALT, 1, uint32(block.timestamp + 1 hours), address(0xDEAD), 1 ether);

        tokenIn.mint(address(spokePool), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(Accumulator.InvalidOriginator.selector, address(0xDEAD)));
        spokePool.deliver(acc, tokenIn, 1 ether, relayer, msg_);
    }

    function test_accumulate_singleFill() public {
        bytes memory msg_ = _accMessage(ZERO_SALT, 1, uint32(block.timestamp + 1 hours), address(mockOwner), 3 ether);

        tokenIn.mint(address(spokePool), 3 ether);
        spokePool.deliver(acc, tokenIn, 3 ether, relayer, msg_);

        bytes32 fillId = _fillId(ZERO_SALT, address(mockOwner), uint32(block.timestamp + 1 hours), 3 ether);
        (uint256 received,,,, FillStatus status) = acc.fills(fillId);
        assertEq(received, 3 ether);
        assertEq(uint8(status), uint8(FillStatus.Accumulating));
    }

    function test_accumulate_emitsFillReady() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        bytes memory msg_ = _accMessage(ZERO_SALT, 1, deadline, address(mockOwner), 3 ether);
        bytes32 fillId = _fillId(ZERO_SALT, address(mockOwner), deadline, 3 ether);

        tokenIn.mint(address(spokePool), 3 ether);
        vm.expectEmit(true, false, false, true);
        emit FillReady(fillId, 3 ether, 3 ether);
        spokePool.deliver(acc, tokenIn, 3 ether, relayer, msg_);
    }

    function test_accumulate_multiplePartialFills() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        bytes memory msg_ = _accMessage(ZERO_SALT, 1, deadline, address(mockOwner), 5 ether);

        tokenIn.mint(address(spokePool), 5 ether);
        spokePool.deliver(acc, tokenIn, 2 ether, relayer, msg_);
        assertEq(acc.reservedByToken(address(tokenIn)), 2 ether);

        spokePool.deliver(acc, tokenIn, 3 ether, relayer, msg_);
        assertEq(acc.reservedByToken(address(tokenIn)), 5 ether);

        bytes32 fillId = _fillId(ZERO_SALT, address(mockOwner), deadline, 5 ether);
        (uint256 received,,,, FillStatus status) = acc.fills(fillId);
        assertEq(received, 5 ether);
        assertEq(uint8(status), uint8(FillStatus.Accumulating));
    }

    function test_accumulate_tokenMismatchReverts() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        // Message expects tokenIn as the outputToken
        bytes memory msg_ = _accMessage(ZERO_SALT, 1, deadline, address(mockOwner), 5 ether);

        tokenIn.mint(address(spokePool), 2 ether);
        spokePool.deliver(acc, tokenIn, 2 ether, relayer, msg_);

        // Delivering tokenOut should revert because message expects tokenIn
        tokenOut.mint(address(spokePool), 2 ether);
        vm.expectRevert();
        spokePool.deliver(acc, tokenOut, 2 ether, relayer, msg_);

        // Original fill unaffected
        assertEq(acc.reservedByToken(address(tokenIn)), 2 ether);
    }

    function test_accumulate_staleOnArrivalRefunds() public {
        uint32 pastDeadline = uint32(block.timestamp - 1);
        bytes memory msg_ = _accMessage(ZERO_SALT, 1, pastDeadline, address(mockOwner), 5 ether);

        tokenIn.mint(address(spokePool), 5 ether);
        spokePool.deliver(acc, tokenIn, 5 ether, relayer, msg_);

        assertEq(tokenIn.balanceOf(address(mockOwner)), 5 ether);
        bytes32 fillId = _fillId(ZERO_SALT, address(mockOwner), pastDeadline, 5 ether);
        (,,,, FillStatus status) = acc.fills(fillId);
        assertEq(uint8(status), uint8(FillStatus.Stale));
    }

    function test_accumulate_lateArrivalAfterStaleAutoRefunded() public {
        uint32 pastDeadline = uint32(block.timestamp - 1);
        bytes memory msg_ = _accMessage(ZERO_SALT, 1, pastDeadline, address(mockOwner), 5 ether);

        tokenIn.mint(address(spokePool), 8 ether);
        spokePool.deliver(acc, tokenIn, 5 ether, relayer, msg_);
        spokePool.deliver(acc, tokenIn, 3 ether, relayer, msg_);

        assertEq(tokenIn.balanceOf(address(mockOwner)), 8 ether);
        assertEq(tokenIn.balanceOf(address(acc)), 0);
    }

    function test_accumulate_sweep_onlyTransfersUnreserved() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        bytes memory msg_ = _accMessage(ZERO_SALT, 1, deadline, address(mockOwner), 10 ether);

        tokenIn.mint(address(spokePool), 6 ether);
        spokePool.deliver(acc, tokenIn, 6 ether, relayer, msg_);

        tokenIn.mint(address(acc), 4 ether);
        vm.prank(address(mockOwner));
        acc.sweep(address(tokenIn));

        assertEq(tokenIn.balanceOf(address(mockOwner)), 4 ether);
        assertEq(tokenIn.balanceOf(address(acc)), 6 ether);
        assertEq(acc.reservedByToken(address(tokenIn)), 6 ether);
    }

    function test_accumulate_differentSaltsCreateDistinctFillIds() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        bytes32 saltA = keccak256("A");
        bytes32 saltB = keccak256("B");

        bytes memory msgA = _accMessage(saltA, 1, deadline, address(mockOwner), 1 ether);
        bytes memory msgB = _accMessage(saltB, 1, deadline, address(mockOwner), 1 ether);

        tokenIn.mint(address(spokePool), 2 ether);
        spokePool.deliver(acc, tokenIn, 1 ether, relayer, msgA);
        spokePool.deliver(acc, tokenIn, 1 ether, relayer, msgB);

        bytes32 fillIdA = _fillId(saltA, address(mockOwner), deadline, 1 ether);
        bytes32 fillIdB = _fillId(saltB, address(mockOwner), deadline, 1 ether);
        assertTrue(fillIdA != fillIdB);

        (uint256 receivedA,,,,) = acc.fills(fillIdA);
        (uint256 receivedB,,,,) = acc.fills(fillIdB);
        assertEq(receivedA, 1 ether);
        assertEq(receivedB, 1 ether);
    }

    function test_setSpokePool_onlyOwner() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        acc.setSpokePool(address(0x1234));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  markStale tests (V-002 fix)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_markStale_refundsPartialFillAfterDeadline() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        bytes memory msg_ = _accMessage(ZERO_SALT, 1, deadline, address(mockOwner), 10 ether);

        tokenIn.mint(address(spokePool), 6 ether);
        spokePool.deliver(acc, tokenIn, 6 ether, relayer, msg_);

        bytes32 fillId = _fillId(ZERO_SALT, address(mockOwner), deadline, 10 ether);

        // Cannot mark stale before deadline
        vm.prank(address(mockOwner));
        vm.expectRevert();
        acc.markStale(fillId);

        // Warp past deadline
        vm.warp(deadline + 1);

        vm.prank(address(mockOwner));
        acc.markStale(fillId);

        // Fill is now Stale, reserved released, tokens refunded
        (uint256 received,,,, FillStatus status) = acc.fills(fillId);
        assertEq(received, 0);
        assertEq(uint8(status), uint8(FillStatus.Stale));
        assertEq(acc.reservedByToken(address(tokenIn)), 0);
        assertEq(tokenIn.balanceOf(address(mockOwner)), 6 ether);
    }

    function test_markStale_revertsForNonOwner() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        bytes memory msg_ = _accMessage(ZERO_SALT, 1, deadline, address(mockOwner), 5 ether);

        tokenIn.mint(address(spokePool), 3 ether);
        spokePool.deliver(acc, tokenIn, 3 ether, relayer, msg_);

        bytes32 fillId = _fillId(ZERO_SALT, address(mockOwner), deadline, 5 ether);
        vm.warp(deadline + 1);

        vm.prank(address(0xDEAD));
        vm.expectRevert();
        acc.markStale(fillId);
    }

    function test_markStale_revertsForAlreadyExecutedFill() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        _accumulateFull(ZERO_SALT, deadline, 5 ether);

        ExecutionParams memory params =
            _buildParams(ZERO_SALT, deadline, 5 ether, 5 ether, address(tokenIn), recipient, destinationCaller);
        acc.executeIntent(params, new bytes32[](0), "");

        bytes32 fillId = _fillId(ZERO_SALT, address(mockOwner), deadline, 5 ether);
        vm.warp(deadline + 1);

        vm.prank(address(mockOwner));
        vm.expectRevert();
        acc.markStale(fillId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Step 2: Execute tests
    // ═══════════════════════════════════════════════════════════════════════════

    function test_execute_mode1_pureTransfer() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        _accumulateFull(ZERO_SALT, deadline, 3 ether);

        ExecutionParams memory params =
            _buildParams(ZERO_SALT, deadline, 3 ether, 3 ether, address(tokenIn), recipient, destinationCaller);
        acc.executeIntent(params, new bytes32[](0), "");

        assertEq(tokenIn.balanceOf(recipient), 3 ether);
        assertEq(acc.reservedByToken(address(tokenIn)), 0);
    }

    function test_execute_mode1_transfersMinOutputAndRemainder() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        _accumulateFull(ZERO_SALT, deadline, 10 ether);

        ExecutionParams memory params =
            _buildParams(ZERO_SALT, deadline, 10 ether, 7 ether, address(tokenIn), recipient, destinationCaller);
        acc.executeIntent(params, new bytes32[](0), "");

        assertEq(tokenIn.balanceOf(recipient), 7 ether);
        assertEq(tokenIn.balanceOf(address(mockOwner)), 3 ether);
        assertEq(tokenIn.balanceOf(address(acc)), 0);
    }

    function test_execute_mode1_revertsWhenFinalOutputTokenMismatch() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        _accumulateFull(ZERO_SALT, deadline, 5 ether);

        ExecutionParams memory params =
            _buildParams(ZERO_SALT, deadline, 5 ether, 5 ether, address(tokenOut), recipient, destinationCaller);
        vm.expectRevert(
            abi.encodeWithSelector(
                Accumulator.InvalidFinalOutputTokenForDirectTransfer.selector, address(tokenIn), address(tokenOut)
            )
        );
        acc.executeIntent(params, new bytes32[](0), "");
    }

    function test_execute_mode2_transformAndTransfer() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        _accumulateFull(ZERO_SALT, deadline, 5 ether);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(swap), value: 0, data: abi.encodeCall(MockSwap.mintToCaller, (address(tokenOut), 8 ether))
        });

        ExecutionParams memory params = _buildParamsWithCalls(
            ZERO_SALT, deadline, 5 ether, 6 ether, address(tokenOut), recipient, destinationCaller, calls
        );
        acc.executeIntent(params, new bytes32[](0), "");

        // Produced 8 OUT, sent 6 to recipient, remainder to owner.
        assertEq(tokenOut.balanceOf(recipient), 6 ether);
        assertEq(tokenOut.balanceOf(address(mockOwner)), 2 ether);
        assertEq(tokenOut.balanceOf(address(acc)), 0);
    }

    function test_execute_mode2_destCallRevertBubblesUp() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        _accumulateFull(ZERO_SALT, deadline, 5 ether);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(swap), value: 0, data: abi.encodeCall(MockSwap.fail, ())});

        ExecutionParams memory params = _buildParamsWithCalls(
            ZERO_SALT, deadline, 5 ether, 5 ether, address(tokenIn), recipient, destinationCaller, calls
        );
        vm.expectRevert(bytes("fail"));
        acc.executeIntent(params, new bytes32[](0), "");
    }

    function test_execute_mode2_insufficientOutputReverts() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        _accumulateFull(ZERO_SALT, deadline, 5 ether);

        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(swap), value: 0, data: abi.encodeCall(MockSwap.mintToCaller, (address(tokenOut), 2 ether))
        });

        ExecutionParams memory params = _buildParamsWithCalls(
            ZERO_SALT, deadline, 5 ether, 6 ether, address(tokenOut), recipient, destinationCaller, calls
        );
        vm.expectRevert(
            abi.encodeWithSelector(Accumulator.InsufficientOutput.selector, address(tokenOut), 2 ether, 6 ether)
        );
        acc.executeIntent(params, new bytes32[](0), "");
    }

    function test_execute_mode3_executeOnly() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        _accumulateFull(ZERO_SALT, deadline, 5 ether);

        // Mode 3: destCalls transfer tokens directly, finalOutputToken = address(0)
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: address(tokenIn),
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", recipient, 5 ether)
        });

        ExecutionParams memory params =
            _buildParamsWithCalls(ZERO_SALT, deadline, 5 ether, 0, address(0), recipient, destinationCaller, calls);
        acc.executeIntent(params, new bytes32[](0), "");

        assertEq(tokenIn.balanceOf(recipient), 5 ether);
        assertEq(tokenIn.balanceOf(address(acc)), 0);
    }

    function test_execute_revertsBeforeThreshold() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        bytes memory msg_ = _accMessage(ZERO_SALT, 1, deadline, address(mockOwner), 5 ether);

        tokenIn.mint(address(spokePool), 2 ether);
        spokePool.deliver(acc, tokenIn, 2 ether, relayer, msg_);

        ExecutionParams memory params =
            _buildParams(ZERO_SALT, deadline, 5 ether, 5 ether, address(tokenIn), recipient, destinationCaller);
        bytes32 fillId = _fillId(ZERO_SALT, address(mockOwner), deadline, 5 ether);
        vm.expectRevert(abi.encodeWithSelector(Accumulator.ThresholdNotMet.selector, fillId, 2 ether, 5 ether));
        acc.executeIntent(params, new bytes32[](0), "");
    }

    function test_execute_revertsForInvalidSignature() public {
        MockOwnerInvalid badOwner = new MockOwnerInvalid();
        Accumulator badAcc = new Accumulator(address(badOwner));
        badAcc.initialize(address(spokePool));

        uint32 deadline = uint32(block.timestamp + 1 hours);
        bytes memory msg_ = _accMessage(ZERO_SALT, 1, deadline, address(badOwner), 3 ether);
        tokenIn.mint(address(spokePool), 3 ether);
        spokePool.deliver(badAcc, tokenIn, 3 ether, relayer, msg_);

        ExecutionParams memory params =
            _buildParams(ZERO_SALT, deadline, 3 ether, 3 ether, address(tokenIn), recipient, destinationCaller);
        vm.expectRevert(Accumulator.InvalidMerkleSignature.selector);
        badAcc.executeIntent(params, new bytes32[](0), "");
    }

    function test_execute_revertsForUnauthorizedDestinationCaller() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        _accumulateFull(ZERO_SALT, deadline, 3 ether);

        ExecutionParams memory params =
            _buildParams(ZERO_SALT, deadline, 3 ether, 3 ether, address(tokenIn), recipient, address(0xBEEF));
        vm.expectRevert(
            abi.encodeWithSelector(Accumulator.UnauthorizedDestinationCaller.selector, address(this), address(0xBEEF))
        );
        acc.executeIntent(params, new bytes32[](0), "");
    }

    function test_execute_permissionlessWhenDestCallerIsZero() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);
        _accumulateFull(ZERO_SALT, deadline, 3 ether);

        ExecutionParams memory params =
            _buildParams(ZERO_SALT, deadline, 3 ether, 3 ether, address(tokenIn), recipient, address(0));

        // Anyone can call when destinationCaller is address(0)
        vm.prank(address(0xDEAD));
        acc.executeIntent(params, new bytes32[](0), "");

        assertEq(tokenIn.balanceOf(recipient), 3 ether);
    }

    function test_execute_perFillOutputIsolation() public {
        uint32 deadline = uint32(block.timestamp + 1 hours);

        // Fill B: accumulate 5 but needs 10 (not ready)
        bytes memory msgB = _accMessage(keccak256("B"), 1, deadline, address(mockOwner), 10 ether);
        tokenIn.mint(address(spokePool), 5 ether);
        spokePool.deliver(acc, tokenIn, 5 ether, relayer, msgB);

        // Fill A: accumulate 5 = ready
        _accumulateFull(keccak256("A"), deadline, 5 ether);

        // Execute A — should only use its own 5, not B's reserved 5
        ExecutionParams memory paramsA =
            _buildParams(keccak256("A"), deadline, 5 ether, 5 ether, address(tokenIn), recipient, destinationCaller);
        acc.executeIntent(paramsA, new bytes32[](0), "");

        assertEq(tokenIn.balanceOf(recipient), 5 ether);
        assertEq(tokenIn.balanceOf(address(acc)), 5 ether);
        assertEq(acc.reservedByToken(address(tokenIn)), 5 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  Helpers
    // ═══════════════════════════════════════════════════════════════════════════

    function _accMessage(
        bytes32 salt,
        uint256 fromChainId,
        uint32 fillDeadline,
        address depositor,
        uint256 sumOutput,
        address outputToken
    ) internal pure returns (bytes memory) {
        return abi.encode(salt, fromChainId, fillDeadline, depositor, sumOutput, outputToken);
    }

    /// @dev Convenience overload — defaults outputToken to address(tokenIn).
    function _accMessage(bytes32 salt, uint256 fromChainId, uint32 fillDeadline, address depositor, uint256 sumOutput)
        internal
        view
        returns (bytes memory)
    {
        return _accMessage(salt, fromChainId, fillDeadline, depositor, sumOutput, address(tokenIn));
    }

    function _fillId(bytes32 salt, address depositor, uint32 fillDeadline, uint256 sumOutput, address outputToken)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(salt, depositor, fillDeadline, sumOutput, outputToken));
    }

    /// @dev Convenience overload — defaults outputToken to address(tokenIn).
    function _fillId(bytes32 salt, address depositor, uint32 fillDeadline, uint256 sumOutput)
        internal
        view
        returns (bytes32)
    {
        return _fillId(salt, depositor, fillDeadline, sumOutput, address(tokenIn));
    }

    /// @dev Accumulate tokenIn to full threshold.
    function _accumulateFull(bytes32 salt, uint32 deadline, uint256 amount) internal {
        bytes memory msg_ = _accMessage(salt, 1, deadline, address(mockOwner), amount);
        tokenIn.mint(address(spokePool), amount);
        spokePool.deliver(acc, tokenIn, amount, relayer, msg_);
    }

    function _buildParams(
        bytes32 salt,
        uint32 fillDeadline,
        uint256 sumOutput,
        uint256 finalMinOutput,
        address finalOutputToken,
        address _recipient,
        address _destinationCaller
    ) internal view returns (ExecutionParams memory) {
        return ExecutionParams({
            salt: salt,
            fillDeadline: fillDeadline,
            sumOutput: sumOutput,
            outputToken: address(tokenIn),
            finalMinOutput: finalMinOutput,
            finalOutputToken: finalOutputToken,
            recipient: _recipient,
            destinationCaller: _destinationCaller,
            destCalls: new Call[](0)
        });
    }

    function _buildParamsWithCalls(
        bytes32 salt,
        uint32 fillDeadline,
        uint256 sumOutput,
        uint256 finalMinOutput,
        address finalOutputToken,
        address _recipient,
        address _destinationCaller,
        Call[] memory calls
    ) internal view returns (ExecutionParams memory) {
        return ExecutionParams({
            salt: salt,
            fillDeadline: fillDeadline,
            sumOutput: sumOutput,
            outputToken: address(tokenIn),
            finalMinOutput: finalMinOutput,
            finalOutputToken: finalOutputToken,
            recipient: _recipient,
            destinationCaller: _destinationCaller,
            destCalls: calls
        });
    }

    receive() external payable {}
}

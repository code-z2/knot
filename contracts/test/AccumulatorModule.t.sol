// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {AccountERC7579} from "openzeppelin-contracts/account/extensions/draft-AccountERC7579.sol";
import {MODULE_TYPE_EXECUTOR, MODULE_TYPE_FALLBACK} from "openzeppelin-contracts/interfaces/draft-IERC7579.sol";
import {
    ERC7579Utils,
    ExecType,
    Mode,
    ModePayload,
    ModeSelector
} from "openzeppelin-contracts/account/utils/draft-ERC7579Utils.sol";

import {AccumulatorModule} from "../src/AccumulatorModule.sol";
import {IAccumulatorModule} from "../src/interfaces/IAccumulatorModule.sol";
import {IKnotConsumerHub} from "../src/interfaces/IKnotConsumerHub.sol";
import {KnotConsumerHub} from "../src/KnotConsumerHub.sol";
import {Call, ExecutionParams, FillStatus} from "../src/types/Structs.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "MockERC20: insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract MockTarget {
    uint256 public callCount;
    uint256 public lastValue;

    function doSomething(uint256 val) external payable {
        callCount++;
        lastValue = val;
    }
}

contract AccumulatorAccountMock is AccountERC7579 {
    constructor(address module, bytes memory moduleData) {
        _installModule(MODULE_TYPE_EXECUTOR, module, moduleData);
        _installModule(
            MODULE_TYPE_FALLBACK, module, abi.encodePacked(IAccumulatorModule.handleV3AcrossMessage.selector)
        );
        _installModule(MODULE_TYPE_FALLBACK, module, abi.encodePacked(IAccumulatorModule.executeIntent.selector));
        _installModule(MODULE_TYPE_FALLBACK, module, abi.encodePacked(IAccumulatorModule.markStale.selector));
    }

    function selfCall(bytes memory data) external {
        bytes memory executionCalldata = abi.encodePacked(address(this), uint256(0), data);

        Mode mode = ERC7579Utils.encodeMode(
            ERC7579Utils.CALLTYPE_SINGLE,
            ExecType.wrap(0x00),
            ModeSelector.wrap(bytes4(0)),
            ModePayload.wrap(bytes22(0))
        );

        this.execute(Mode.unwrap(mode), executionCalldata);
    }

    function uninstallExecutor(address module) external {
        _uninstallModule(MODULE_TYPE_EXECUTOR, module, "");
    }

    function _rawSignatureValidation(bytes32, bytes calldata) internal view override returns (bool) {
        return false;
    }
}

contract AccumulatorModuleTest is Test {
    AccumulatorModule module;
    AccumulatorAccountMock account;
    MockERC20 token;
    MockTarget target;
    KnotConsumerHub hub;

    address spokePool = makeAddr("spokePool");
    address relayer = address(0xBEEF);
    address recipient = address(0xCAFE);

    bytes32 constant SALT = keccak256("test-salt");
    uint256 constant FROM_CHAIN_ID = 1;
    uint32 constant FILL_DEADLINE_OFFSET = 1 hours;
    uint256 constant SUM_OUTPUT = 1000;

    function setUp() public {
        module = new AccumulatorModule();
        token = new MockERC20();
        target = new MockTarget();
        hub = new KnotConsumerHub(makeAddr("executorModule"), address(module));

        account = new AccumulatorAccountMock(address(module), abi.encode(spokePool, address(hub)));
        token.mint(address(account), 10_000);
    }

    function test_onInstall_setsSpokePool() public view {
        assertEq(module.spokePools(address(account)), spokePool);
    }

    function test_onInstall_revertsForZeroAddress() public {
        vm.expectRevert(AccumulatorModule.InvalidSpokePool.selector);
        vm.prank(address(account));
        module.onInstall(abi.encode(address(0), address(hub)));
    }

    function test_onInstall_revertsForZeroConsumerHub() public {
        vm.expectRevert(AccumulatorModule.InvalidConsumerHub.selector);
        vm.prank(address(account));
        module.onInstall(abi.encode(spokePool, address(0)));
    }

    function test_onUninstall_clearsConfig() public {
        vm.prank(address(account));
        module.onUninstall("");

        assertEq(module.spokePools(address(account)), address(0));
    }

    function test_isModuleType_executor() public view {
        assertTrue(module.isModuleType(MODULE_TYPE_EXECUTOR));
    }

    function test_isModuleType_fallback() public view {
        assertTrue(module.isModuleType(MODULE_TYPE_FALLBACK));
    }

    function test_isModuleType_validator_returnsFalse() public view {
        assertFalse(module.isModuleType(1));
    }

    function test_handleV3AcrossMessage_accumulatesTokens() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), 400);

        (uint256 received,,, uint32 storedDeadline, FillStatus status) = module.fills(address(account), fillId);
        assertEq(received, 400);
        assertEq(uint8(status), uint8(FillStatus.Accumulating));
        assertEq(storedDeadline, deadline);

        _simulateFill(SALT, 10, deadline, SUM_OUTPUT, address(token), 300);

        (received,,,,) = module.fills(address(account), fillId);
        assertEq(received, 700);
    }

    function test_handleV3AcrossMessage_revertsIfNotSpokePool() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        address fakeSpokePool = address(0xBAD);
        bytes memory message = abi.encode(SALT, FROM_CHAIN_ID, deadline, address(account), SUM_OUTPUT, address(token));

        vm.expectRevert(abi.encodeWithSelector(AccumulatorModule.NotSpokePool.selector, fakeSpokePool));
        vm.prank(fakeSpokePool);
        IAccumulatorModule(address(account)).handleV3AcrossMessage(address(token), 400, relayer, message);
    }

    function test_handleV3AcrossMessage_revertsIfInvalidDepositor() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        address wrongDepositor = address(0xDEAD);
        bytes memory message = abi.encode(SALT, FROM_CHAIN_ID, deadline, wrongDepositor, SUM_OUTPUT, address(token));

        vm.expectRevert(abi.encodeWithSelector(AccumulatorModule.InvalidDepositor.selector, wrongDepositor));
        vm.prank(spokePool);
        IAccumulatorModule(address(account)).handleV3AcrossMessage(address(token), 400, relayer, message);
    }

    function test_handleV3AcrossMessage_revertsIfTokenMismatch() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        address wrongToken = address(0x1234);
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));
        bytes memory message = abi.encode(SALT, FROM_CHAIN_ID, deadline, address(account), SUM_OUTPUT, address(token));

        vm.expectRevert(
            abi.encodeWithSelector(AccumulatorModule.TokenMismatch.selector, fillId, wrongToken, address(token))
        );
        vm.prank(spokePool);
        IAccumulatorModule(address(account)).handleV3AcrossMessage(wrongToken, 400, relayer, message);
    }

    function test_handleV3AcrossMessage_ignoresExecutedFills() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), SUM_OUTPUT);
        _executeIntent(SALT, deadline, SUM_OUTPUT, address(token), 900, address(token), recipient);
        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), 100);

        (uint256 received,,,,) = module.fills(address(account), fillId);
        assertEq(received, SUM_OUTPUT);
    }

    function test_handleV3AcrossMessage_ignoresStaleFills() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), 400);
        vm.warp(deadline + 1);
        account.selfCall(abi.encodeCall(IAccumulatorModule.markStale, (fillId)));
        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), 100);

        (uint256 received,,,,) = module.fills(address(account), fillId);
        assertEq(received, 400);
    }

    function test_handleV3AcrossMessage_marksStaleIfExpired() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        vm.warp(deadline + 1);

        vm.expectEmit(true, true, true, true, address(hub));
        emit IKnotConsumerHub.IntentStale(fillId, address(account), block.chainid);

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), 400);

        (,,,, FillStatus status) = module.fills(address(account), fillId);
        assertEq(uint8(status), uint8(FillStatus.Stale));
    }

    function test_handleV3AcrossMessage_emitsFillAccumulated() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        vm.expectEmit(true, true, false, true);
        emit IAccumulatorModule.FillAccumulated(fillId, address(token), 400, 400, SUM_OUTPUT);

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), 400);
    }

    function test_handleV3AcrossMessage_reportsFillReadyWhenThresholdMet() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        vm.expectEmit(true, true, true, true, address(hub));
        emit IKnotConsumerHub.FillReady(fillId, address(account), block.chainid);

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), SUM_OUTPUT);
    }

    function test_handleV3AcrossMessage_reportsFillReadyToHub() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        vm.expectEmit(true, true, true, true, address(hub));
        emit IKnotConsumerHub.FillReady(fillId, address(account), block.chainid);

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), SUM_OUTPUT);
    }

    function test_handleV3AcrossMessage_reportsFillReadyWhenExceedingThreshold() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        vm.expectEmit(true, true, true, true, address(hub));
        emit IKnotConsumerHub.FillReady(fillId, address(account), block.chainid);

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), SUM_OUTPUT + 200);
    }

    function test_handleV3AcrossMessage_deduplicatesSourceChainIds() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), 400);
        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), 300);
        _simulateFill(SALT, 42161, deadline, SUM_OUTPUT, address(token), 300);

        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));
        (uint256 received,,,,) = module.fills(address(account), fillId);
        assertEq(received, 1000);
    }

    function test_executeIntent_pureTransfer() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));
        uint256 finalMinOutput = 900;

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), SUM_OUTPUT);

        vm.expectEmit(true, true, true, true, address(hub));
        emit IKnotConsumerHub.IntentExecuted(fillId, address(account), block.chainid);
        _executeIntent(SALT, deadline, SUM_OUTPUT, address(token), finalMinOutput, address(token), recipient);

        (,,,, FillStatus status) = module.fills(address(account), fillId);
        assertEq(uint8(status), uint8(FillStatus.Executed));
        assertEq(token.balanceOf(recipient), finalMinOutput);
    }

    function test_executeIntent_dropsWhenFillFundsWereSpent() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), SUM_OUTPUT);

        // Spend enough of the fungible token balance that the fill can no longer be satisfied.
        vm.prank(address(account));
        token.transfer(address(0xBEEF), 9200);

        vm.expectEmit(true, true, true, true, address(hub));
        emit IKnotConsumerHub.IntentDropped(fillId, address(account), block.chainid);

        _executeIntent(SALT, deadline, SUM_OUTPUT, address(token), 900, address(token), recipient);

        (,,,, FillStatus status) = module.fills(address(account), fillId);
        assertEq(uint8(status), uint8(FillStatus.Dropped));
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_executeIntent_executeOnlyMode() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), SUM_OUTPUT);

        Call[] memory destCalls = new Call[](1);
        destCalls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(MockTarget.doSomething, (42))});

        ExecutionParams memory params = ExecutionParams({
            salt: SALT,
            fillDeadline: deadline,
            sumOutput: SUM_OUTPUT,
            outputToken: address(token),
            finalMinOutput: 0,
            finalOutputToken: address(0),
            recipient: address(0),
            destinationCaller: address(0),
            destCalls: destCalls
        });

        account.selfCall(abi.encodeCall(IAccumulatorModule.executeIntent, (params)));

        (,,,, FillStatus status) = module.fills(address(account), fillId);
        assertEq(uint8(status), uint8(FillStatus.Executed));
        assertEq(target.callCount(), 1);
        assertEq(target.lastValue(), 42);
    }

    function test_executeIntent_revertsIfNotSelfCall() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), SUM_OUTPUT);

        ExecutionParams memory params =
            _buildPureTransferParams(SALT, deadline, SUM_OUTPUT, address(token), 900, address(token), recipient);

        vm.expectRevert(abi.encodeWithSelector(AccumulatorModule.NotSelfCall.selector, address(this)));
        vm.prank(address(account));
        bytes memory callData = abi.encodeCall(IAccumulatorModule.executeIntent, (params));
        (bool ok, bytes memory ret) = address(module).call(abi.encodePacked(callData, address(this)));
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
    }

    function test_executeIntent_revertsIfNotAccumulating() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), SUM_OUTPUT);
        _executeIntent(SALT, deadline, SUM_OUTPUT, address(token), 900, address(token), recipient);

        ExecutionParams memory params =
            _buildPureTransferParams(SALT, deadline, SUM_OUTPUT, address(token), 900, address(token), recipient);

        vm.expectRevert(
            abi.encodeWithSelector(AccumulatorModule.InvalidFillStatus.selector, fillId, FillStatus.Executed)
        );
        account.selfCall(abi.encodeCall(IAccumulatorModule.executeIntent, (params)));
    }

    function test_executeIntent_revertsIfDropped() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), SUM_OUTPUT);

        vm.prank(address(account));
        token.transfer(address(0xBEEF), 9200);

        _executeIntent(SALT, deadline, SUM_OUTPUT, address(token), 900, address(token), recipient);

        ExecutionParams memory params =
            _buildPureTransferParams(SALT, deadline, SUM_OUTPUT, address(token), 900, address(token), recipient);

        vm.expectRevert(
            abi.encodeWithSelector(AccumulatorModule.InvalidFillStatus.selector, fillId, FillStatus.Dropped)
        );
        account.selfCall(abi.encodeCall(IAccumulatorModule.executeIntent, (params)));
    }

    function test_executeIntent_revertsIfThresholdNotMet() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), 500);

        ExecutionParams memory params =
            _buildPureTransferParams(SALT, deadline, SUM_OUTPUT, address(token), 400, address(token), recipient);

        vm.expectRevert(abi.encodeWithSelector(AccumulatorModule.ThresholdNotMet.selector, fillId, 500, SUM_OUTPUT));
        account.selfCall(abi.encodeCall(IAccumulatorModule.executeIntent, (params)));
    }

    function test_executeIntent_reportsIntentExecutedToHub() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        uint256 finalMinOutput = 900;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), SUM_OUTPUT);

        vm.expectEmit(true, true, true, true, address(hub));
        emit IKnotConsumerHub.IntentExecuted(fillId, address(account), block.chainid);

        _executeIntent(SALT, deadline, SUM_OUTPUT, address(token), finalMinOutput, address(token), recipient);
    }

    function test_markStale_marksExpiredFill() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), 400);

        vm.warp(deadline + 1);
        account.selfCall(abi.encodeCall(IAccumulatorModule.markStale, (fillId)));

        (,,,, FillStatus status) = module.fills(address(account), fillId);
        assertEq(uint8(status), uint8(FillStatus.Stale));
    }

    function test_markStale_reportsIntentStaleToHub() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), 400);
        vm.warp(deadline + 1);

        vm.expectEmit(true, true, true, true, address(hub));
        emit IKnotConsumerHub.IntentStale(fillId, address(account), block.chainid);

        account.selfCall(abi.encodeCall(IAccumulatorModule.markStale, (fillId)));
    }

    function test_markStale_revertsIfNotSelfCall() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), 400);
        vm.warp(deadline + 1);

        vm.expectRevert(abi.encodeWithSelector(AccumulatorModule.NotSelfCall.selector, address(this)));
        vm.prank(address(account));
        (bool ok, bytes memory ret) = address(module)
            .call(abi.encodePacked(abi.encodeCall(IAccumulatorModule.markStale, (fillId)), address(this)));
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
    }

    function test_markStale_revertsIfNotExpired() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), 400);

        vm.expectRevert(abi.encodeWithSelector(AccumulatorModule.FillNotExpired.selector, fillId, deadline));
        account.selfCall(abi.encodeCall(IAccumulatorModule.markStale, (fillId)));
    }

    function test_markStale_revertsIfNotAccumulating() public {
        uint32 deadline = uint32(block.timestamp) + FILL_DEADLINE_OFFSET;
        bytes32 fillId = _fillId(SALT, address(account), deadline, SUM_OUTPUT, address(token));

        _simulateFill(SALT, FROM_CHAIN_ID, deadline, SUM_OUTPUT, address(token), SUM_OUTPUT);
        _executeIntent(SALT, deadline, SUM_OUTPUT, address(token), 900, address(token), recipient);

        vm.warp(deadline + 1);

        vm.expectRevert(
            abi.encodeWithSelector(AccumulatorModule.InvalidFillStatus.selector, fillId, FillStatus.Executed)
        );
        account.selfCall(abi.encodeCall(IAccumulatorModule.markStale, (fillId)));
    }

    function _simulateFill(
        bytes32 salt,
        uint256 fromChainId,
        uint32 fillDeadline,
        uint256 sumOutput,
        address outputToken,
        uint256 amount
    ) internal {
        bytes memory message = abi.encode(salt, fromChainId, fillDeadline, address(account), sumOutput, outputToken);

        vm.prank(spokePool);
        IAccumulatorModule(address(account)).handleV3AcrossMessage(outputToken, amount, relayer, message);
    }

    function _executeIntent(
        bytes32 salt,
        uint32 fillDeadline,
        uint256 sumOutput,
        address outputToken,
        uint256 finalMinOutput,
        address finalOutputToken,
        address rec
    ) internal {
        ExecutionParams memory params = _buildPureTransferParams(
            salt, fillDeadline, sumOutput, outputToken, finalMinOutput, finalOutputToken, rec
        );
        account.selfCall(abi.encodeCall(IAccumulatorModule.executeIntent, (params)));
    }

    function _buildPureTransferParams(
        bytes32 salt,
        uint32 fillDeadline,
        uint256 sumOutput,
        address outputToken,
        uint256 finalMinOutput,
        address finalOutputToken,
        address rec
    ) internal pure returns (ExecutionParams memory) {
        Call[] memory noCalls = new Call[](0);
        return ExecutionParams({
            salt: salt,
            fillDeadline: fillDeadline,
            sumOutput: sumOutput,
            outputToken: outputToken,
            finalMinOutput: finalMinOutput,
            finalOutputToken: finalOutputToken,
            recipient: rec,
            destinationCaller: address(0),
            destCalls: noCalls
        });
    }

    function _fillId(bytes32 salt, address depositor, uint32 fillDeadline, uint256 sumOutput, address outputToken)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(salt, depositor, fillDeadline, sumOutput, outputToken));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {
    Execution,
    IERC7579Execution,
    IERC7579Module,
    MODULE_TYPE_EXECUTOR,
    MODULE_TYPE_FALLBACK
} from "openzeppelin-contracts/interfaces/draft-IERC7579.sol";
import {
    ERC7579Utils,
    CallType,
    ExecType,
    Mode,
    ModePayload,
    ModeSelector
} from "openzeppelin-contracts/account/utils/draft-ERC7579Utils.sol";

import {IAccumulatorModule} from "./interfaces/IAccumulatorModule.sol";
import {Call, ExecutionParams, FillState, FillStatus} from "./types/Structs.sol";

/// @title AccumulatorModule
/// @notice ERC-7579 executor + fallback handler module for destination-chain fill tracking
///         and intent execution. Singleton — one deployment serves all accounts.
///
/// @dev Dual module type:
///      - Type 2 (Executor): Calls `executeFromExecutor` on the account to move tokens.
///      - Type 3 (Fallback Handler): Routes `handleV3AcrossMessage`, `executeIntent`, and
///        `markStale` through the account's `fallback()` to this module.
///
///      Tokens stay at the account. The module only tracks metadata. When a fill goes stale,
///      no refund is needed because the tokens are already at the account.
///
///      Auth model:
///        - handleV3AcrossMessage: SpokePool calls account → fallback routes here.
///          Verified via `_msgSender()` (ERC-2771) == spokePools[account].
///        - executeIntent / markStale: owner self-call via account.execute → fallback routes here.
///          Verified via `_msgSender()` == account (self-call).
contract AccumulatorModule is IAccumulatorModule, IERC7579Module {
    // ═══════════════════════════════════════════════════════════════════════════
    //                                CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Sentinel address representing native TOKEN for `finalOutputToken`.
    address private constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Per-account SpokePool config.
    mapping(address account => address spokePool) public spokePools;

    /// @notice Per-account fill tracking.
    mapping(address account => mapping(bytes32 fillId => FillState)) public fills;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidSpokePool();
    error NotSpokePool(address caller);
    error NotSelfCall(address caller);
    error InvalidDepositor(address depositor);
    error TokenMismatch(bytes32 fillId, address tokenSent, address outputToken);
    error InvalidFillStatus(bytes32 fillId, FillStatus status);
    error ThresholdNotMet(bytes32 fillId, uint256 received, uint256 sumOutput);
    error FillNotExpired(bytes32 fillId, uint32 fillDeadline);
    error InvalidExecutionMode();

    // ═══════════════════════════════════════════════════════════════════════════
    //                            MODULE LIFECYCLE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Installs the module for the calling account.
    /// @dev Data layout: `abi.encode(address spokePool)`.
    ///      When installed as a fallback handler (type 3), OZ passes empty data after the
    ///      selector — skip config in that case (already set by the executor install).
    function onInstall(bytes calldata data) external {
        if (data.length == 0) return;
        address spokePool = abi.decode(data, (address));
        if (spokePool == address(0)) revert InvalidSpokePool();
        spokePools[msg.sender] = spokePool;
    }

    /// @notice Removes the module config for the calling account.
    function onUninstall(bytes calldata) external {
        delete spokePools[msg.sender];
    }

    /// @notice Returns whether this module implements executor or fallback handler types.
    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR || moduleTypeId == MODULE_TYPE_FALLBACK;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                    STEP 1: ACCUMULATE (SpokePool fills)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Across V3 callback — accumulates bridged tokens. No execution occurs here.
    /// @dev Called via: SpokePool → account.handleV3AcrossMessage → fallback → this module.
    ///      msg.sender = account, _msgSender() = SpokePool (ERC-2771 appended by fallback).
    function handleV3AcrossMessage(
        address tokenSent,
        uint256 amount,
        address, /* relayer */
        bytes memory message
    )
        external
        payable
    {
        address account = msg.sender;
        address caller = _msgSender();

        if (caller != spokePools[account]) revert NotSpokePool(caller);

        (
            bytes32 salt,
            uint256 fromChainId,
            uint32 fillDeadline,
            address depositor,
            uint256 sumOutput,
            address outputToken
        ) = abi.decode(message, (bytes32, uint256, uint32, address, uint256, address));

        if (depositor != account) revert InvalidDepositor(depositor);

        bytes32 fillId = keccak256(abi.encode(salt, depositor, fillDeadline, sumOutput, outputToken));

        if (tokenSent != outputToken) revert TokenMismatch(fillId, tokenSent, outputToken);

        FillState storage state = fills[account][fillId];

        // Already terminal — ignore.
        if (
            state.status == FillStatus.Executed || state.status == FillStatus.Dropped
                || state.status == FillStatus.Stale
        ) return;

        // Expired — mark stale. Tokens stay at the account.
        if (block.timestamp > fillDeadline) {
            state.status = FillStatus.Stale;
            emit FillStale(fillId, fillDeadline);
            return;
        }

        // Initialize on first fill.
        if (state.received == 0) {
            state.inputToken = tokenSent;
            state.sumOutput = sumOutput;
            state.fillDeadline = fillDeadline;
            state.status = FillStatus.Accumulating;
        }

        state.received += amount;
        _recordSourceChainId(state, fromChainId);

        emit FillAccumulated(fillId, tokenSent, amount, state.received, sumOutput);

        if (state.received >= sumOutput) {
            emit FillReady(fillId, state.received, sumOutput);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                    STEP 2: EXECUTE (owner-gated)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Execute an accumulated intent.
    /// @dev Called via: UserOp → account.execute(self.executeIntent(params)) → fallback → here.
    ///      msg.sender = account, _msgSender() = account (self-call).
    ///      No signature verification — the UserOp was already validated by MerkleValidator.
    function executeIntent(ExecutionParams calldata params) external {
        address account = msg.sender;
        if (_msgSender() != account) revert NotSelfCall(_msgSender());

        bytes32 fillId =
            keccak256(abi.encode(params.salt, account, params.fillDeadline, params.sumOutput, params.outputToken));

        FillState storage state = fills[account][fillId];

        if (state.status != FillStatus.Accumulating) {
            revert InvalidFillStatus(fillId, state.status);
        }
        if (state.received < state.sumOutput) {
            revert ThresholdNotMet(fillId, state.received, state.sumOutput);
        }

        uint256 availableBalance = _balanceOf(account, state.inputToken);
        if (availableBalance < state.received) {
            state.status = FillStatus.Dropped;
            emit FillDropped(fillId, state.inputToken, availableBalance, state.received);
            return;
        }

        bool hasDestCalls = params.destCalls.length > 0;
        address finalOut = params.finalOutputToken;

        if (!hasDestCalls && finalOut != address(0)) {
            // Mode 1: Pure Transfer
            _executeTransfer(account, finalOut, params.recipient, params.finalMinOutput);
        } else if (hasDestCalls && finalOut != address(0)) {
            // Mode 2: Transform + Transfer
            _executeCallsViaAccount(account, params.destCalls);
            _executeTransfer(account, finalOut, params.recipient, params.finalMinOutput);
        } else if (hasDestCalls && finalOut == address(0)) {
            // Mode 3: Execute Only
            _executeCallsViaAccount(account, params.destCalls);
        } else {
            revert InvalidExecutionMode();
        }

        state.status = FillStatus.Executed;
        emit FillExecuted(fillId, params.recipient, finalOut, params.finalMinOutput);
    }

    /// @notice Mark an expired fill as stale.
    /// @dev Called via self-call. Tokens stay at the account — no refund needed.
    function markStale(bytes32 fillId) external {
        address account = msg.sender;
        if (_msgSender() != account) revert NotSelfCall(_msgSender());

        FillState storage state = fills[account][fillId];

        if (state.status != FillStatus.Accumulating) {
            revert InvalidFillStatus(fillId, state.status);
        }
        if (block.timestamp <= state.fillDeadline) {
            revert FillNotExpired(fillId, state.fillDeadline);
        }

        state.status = FillStatus.Stale;

        emit FillStale(fillId, state.fillDeadline);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         ACCOUNT EXECUTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Transfers tokens from the account to the recipient via executeFromExecutor.
    function _executeTransfer(address account, address token, address recipient, uint256 amount) internal {
        bytes memory calls;

        if (token == NATIVE) {
            calls = abi.encodePacked(recipient, amount, "");
        } else {
            calls = abi.encodePacked(token, uint256(0), abi.encodeCall(IERC20.transfer, (recipient, amount)));
        }

        IERC7579Execution(account).executeFromExecutor(Mode.unwrap(_encodeMode(ERC7579Utils.CALLTYPE_SINGLE)), calls);
    }

    /// @dev Executes destination calls through the account as a batch.
    function _executeCallsViaAccount(address account, Call[] calldata calls) internal {
        Execution[] memory executions = new Execution[](calls.length);
        for (uint256 i; i < calls.length; i++) {
            executions[i] = Execution({target: calls[i].target, value: calls[i].value, callData: calls[i].data});
        }

        IERC7579Execution(account)
            .executeFromExecutor(
                Mode.unwrap(_encodeMode(ERC7579Utils.CALLTYPE_BATCH)), ERC7579Utils.encodeBatch(executions)
            );
    }

    /// @dev Builds an ERC-7579 execution mode.
    function _encodeMode(CallType callType) internal pure returns (Mode) {
        return ERC7579Utils.encodeMode(
            callType, ExecType.wrap(0x00), ModeSelector.wrap(bytes4(0)), ModePayload.wrap(bytes22(0))
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                              UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Appends source chain id once (deduplicated) for event/UI attribution.
    function _recordSourceChainId(FillState storage state, uint256 sourceChainId) internal {
        uint256 len = state.sourceChainIds.length;
        for (uint256 i; i < len; i++) {
            if (state.sourceChainIds[i] == sourceChainId) return;
        }
        state.sourceChainIds.push(sourceChainId);
    }

    /// @dev Returns the account balance for the tracked fill asset.
    function _balanceOf(address account, address token) internal view returns (uint256) {
        if (token == NATIVE) return account.balance;
        return IERC20(token).balanceOf(account);
    }

    /// @dev Extracts the original msg.sender from ERC-2771 appended calldata.
    ///      The account's fallback appends `abi.encodePacked(msg.data, msg.sender)`.
    function _msgSender() internal pure returns (address sender) {
        assembly {
            sender := shr(96, calldataload(sub(calldatasize(), 20)))
        }
    }
}

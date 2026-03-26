// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IKnotConsumerHub} from "./interfaces/IKnotConsumerHub.sol";

/// @title KnotConsumerHub
/// @notice Canonical global event surface for Knot cross-chain intent orchestration.
///
/// @dev The hub is deliberately narrow:
///      - it does not execute user funds
///      - it does not custody assets
///      - it does not enforce cross-chain lifecycle correctness
///
///      The hub authenticates the canonical module singletons and emits idempotent lifecycle
///      events that Goldsky can index across chains. It stores only the minimum per-fill state
///      required to make those notifications repeat-safe.
contract KnotConsumerHub is IKnotConsumerHub {
    // ═══════════════════════════════════════════════════════════════════════════
    //                                 TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    enum IntentStatus {
        None,
        Ready,
        Executed,
        Dropped,
        Stale
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                                IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Canonical CrossChainExecutor singleton allowed to register intents.
    address public immutable executorModule;

    /// @notice Canonical AccumulatorModule singleton allowed to report destination lifecycle.
    address public immutable accumulatorModule;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 STATE
    // ═══════════════════════════════════════════════════════════════════════════

    mapping(bytes32 key => bool registered) internal _registered;
    mapping(bytes32 key => IntentStatus status) internal _statuses;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error InvalidModule();
    error UnauthorizedExecutor(address caller);
    error UnauthorizedAccumulator(address caller);

    // ═══════════════════════════════════════════════════════════════════════════
    //                               CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    constructor(address executor, address accumulator) {
        if (executor == address(0) || accumulator == address(0)) {
            revert InvalidModule();
        }
        executorModule = executor;
        accumulatorModule = accumulator;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         SOURCE REGISTRATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Emit the canonical source-chain registration event for a deferred intent.
    /// @dev Idempotent per `(account, fillId)`. Only the configured executor module may call.
    function registerIntent(address account, bytes32 fillId, uint256 destinationChainId, uint32 fillDeadline) external {
        if (msg.sender != executorModule) {
            revert UnauthorizedExecutor(msg.sender);
        }

        bytes32 key = _key(account, fillId);
        if (_registered[key]) {
            return;
        }
        _registered[key] = true;

        emit IntentRegistered(fillId, account, destinationChainId, block.chainid, fillDeadline);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                      DESTINATION LIFECYCLE REPORTING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Emit the canonical ready event once a fill reaches threshold on destination.
    function reportFillReady(address account, bytes32 fillId) external {
        if (msg.sender != accumulatorModule) {
            revert UnauthorizedAccumulator(msg.sender);
        }

        bytes32 key = _key(account, fillId);
        IntentStatus status = _statuses[key];
        if (status != IntentStatus.None) {
            return;
        }

        _statuses[key] = IntentStatus.Ready;
        emit FillReady(fillId, account, block.chainid);
    }

    /// @notice Emit the canonical executed event for a deferred intent.
    function reportIntentExecuted(address account, bytes32 fillId) external {
        if (msg.sender != accumulatorModule) {
            revert UnauthorizedAccumulator(msg.sender);
        }
        if (_advanceToTerminal(account, fillId, IntentStatus.Executed)) {
            emit IntentExecuted(fillId, account, block.chainid);
        }
    }

    /// @notice Emit the canonical dropped event when the account no longer holds fill funds.
    function reportIntentDropped(address account, bytes32 fillId) external {
        if (msg.sender != accumulatorModule) {
            revert UnauthorizedAccumulator(msg.sender);
        }
        if (_advanceToTerminal(account, fillId, IntentStatus.Dropped)) {
            emit IntentDropped(fillId, account, block.chainid);
        }
    }

    /// @notice Emit the canonical stale event for an expired fill.
    function reportIntentStale(address account, bytes32 fillId) external {
        if (msg.sender != accumulatorModule) {
            revert UnauthorizedAccumulator(msg.sender);
        }
        if (_advanceToTerminal(account, fillId, IntentStatus.Stale)) {
            emit IntentStale(fillId, account, block.chainid);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                              UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Advances `(account, fillId)` into a terminal destination status.
    ///      Repeated reports of the same terminal state are ignored. Conflicting terminal
    ///      reports are also ignored so orchestration cannot brick account execution paths.
    function _advanceToTerminal(address account, bytes32 fillId, IntentStatus next) internal returns (bool changed) {
        bytes32 key = _key(account, fillId);
        IntentStatus current = _statuses[key];

        if (current == next) {
            return false;
        }
        if (current == IntentStatus.Executed || current == IntentStatus.Dropped || current == IntentStatus.Stale) {
            return false;
        }

        _statuses[key] = next;
        return true;
    }

    /// @dev Derives the idempotency key for one account/fill pair.
    function _key(address account, bytes32 fillId) internal pure returns (bytes32) {
        return keccak256(abi.encode(account, fillId));
    }
}

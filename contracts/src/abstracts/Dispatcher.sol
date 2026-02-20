// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

import {IDispatcher} from "../interfaces/IDispatcher.sol";
import {ISpokePool} from "../interfaces/ISpokePool.sol";

import {OnchainCrossChainOrder, DispatchOrder, AcrossOrderData} from "../types/Structs.sol";

/// @title Dispatcher
/// @notice Abstract base for dispatching cross-chain orders through the Across SpokePool.
/// @dev Inheriting contracts must implement `_getAccumulator` and enforce access control
///      so that `dispatch` is only callable via self-call (e.g. from `executeX` batch).
///
///      Native token handling: The Dispatcher does NOT wrap/unwrap native tokens.
///      If the user provides native ETH (msg.value), it is forwarded directly to the SpokePool
///      deposit call. Across treats a deposit with a WETH input token address and positive msg.value
///      as a native deposit. If wrapping is needed before deposit, it must be encoded as a
///      preceding call in the executeX Call[] batch.
///
///      Flow: executeX -> [sourceCalls...] -> dispatch(order) -> SpokePool.deposit
abstract contract Dispatcher is IDispatcher {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                CONFIG
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Across SpokePool used for deposit calls (set at initialize).
    ISpokePool public spokePool;

    // ═══════════════════════════════════════════════════════════════════════════
    //                           ABSTRACT HOOKS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Returns the accumulator address on the destination chain that receives bridged tokens.
    function _getAccumulator() internal view virtual returns (address);

    // ═══════════════════════════════════════════════════════════════════════════
    //                              DISPATCH
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Dispatch a single cross-chain leg via the SpokePool.
    /// @dev    Access: onlyEntryPointOrSelf — called via self-call from executeX batch.
    ///         No signature verification here; auth is enforced at the executeX layer.
    ///         Replay protection is handled by executeX's salt tracking.
    ///
    ///         Native ETH handling: If msg.value > 0, it is forwarded to the SpokePool.
    ///         Across treats WETH address + msg.value as a native deposit.
    ///         For ERC-20 inputs, the token is approved to the SpokePool.
    ///
    /// @param envelope ERC-7683 OnchainCrossChainOrder with fillDeadline in the envelope
    ///                 and DispatchOrder abi-encoded in orderData.
    function _dispatch(OnchainCrossChainOrder calldata envelope) internal virtual {
        DispatchOrder memory order = abi.decode(envelope.orderData, (DispatchOrder));

        // Build the slim destination message (accumulation-only fields).
        (bytes32 jobId, bytes memory message) = _buildDestinationMessage(order, envelope.fillDeadline);

        // Resolve msg.value vs ERC-20 approval.
        uint256 value;
        if (msg.value > 0) {
            value = msg.value;
        } else {
            IERC20(order.inputToken).forceApprove(address(spokePool), order.inputAmount);
        }

        // Build Across order data.
        AcrossOrderData memory acrossOrderData = AcrossOrderData({
            depositor: _toBytes32(msg.sender),
            recipient: _toBytes32(_getAccumulator()),
            inputToken: _toBytes32(order.inputToken),
            outputToken: _toBytes32(order.outputToken),
            inputAmount: order.inputAmount,
            outputAmount: order.minOutput,
            destinationChainId: order.destChainId,
            exclusiveRelayer: bytes32(0),
            exclusivityParameter: uint32(0),
            message: message
        });

        _callDeposit(envelope.fillDeadline, value, acrossOrderData);
        emit CrossChainOrderDispatched(jobId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         SPOKE POOL INTERACTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Forwards the resolved order to `SPOKE_POOL.deposit`.
    ///      Uses `block.timestamp` as quote timestamp and caller-provided `fillDeadline`.
    function _callDeposit(uint32 fillDeadline, uint256 value, AcrossOrderData memory data) internal virtual {
        spokePool.deposit{value: value}(
            data.depositor,
            data.recipient,
            data.inputToken,
            data.outputToken,
            data.inputAmount,
            data.outputAmount,
            data.destinationChainId,
            data.exclusiveRelayer,
            SafeCast.toUint32(block.timestamp),
            fillDeadline,
            data.exclusivityParameter,
            data.message
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                        DESTINATION MESSAGE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Encodes the slim accumulation-only message consumed by the Accumulator and derives the job ID.
    ///
    ///      The message contains ONLY fields needed for accumulation (no execution parameters).
    ///      Execution parameters (recipient, finalOutputToken, destCalls, etc.) are provided later
    ///      in `executeIntent` and authenticated via the owner's Merkle signature.
    ///
    ///      Message fields:
    ///        - salt: Stable intent discriminator for fillId derivation.
    ///        - fromChainId: Source chain ID (excluded from fillId so multi-chain fills aggregate).
    ///        - fillDeadline: Accumulation expiry timestamp (from OnchainCrossChainOrder envelope).
    ///        - depositor: msg.sender — the account dispatching (validated as owner() by Accumulator).
    ///        - sumOutput: Total accumulation threshold across all source chains.
    ///        - outputToken: Expected token to be delivered on the destination chain (V-001 fix:
    ///          prevents fill poisoning by binding the fill to the expected token).
    function _buildDestinationMessage(DispatchOrder memory order, uint32 fillDeadline)
        internal
        view
        returns (bytes32 jobId, bytes memory message)
    {
        message = abi.encode(order.salt, block.chainid, fillDeadline, msg.sender, order.sumOutput, order.outputToken);
        jobId = keccak256(message);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                              UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Left-pads an address into a bytes32 (Across V3 deposit format).
    function _toBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
}

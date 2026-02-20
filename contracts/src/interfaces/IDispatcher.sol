// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {OnchainCrossChainOrder} from "../types/Structs.sol";

/// @title IDispatcher
/// @notice Dispatches cross-chain orders to the SpokePool.
///         Called via self-call from executeX (no signature verification — auth is at the executeX layer).
interface IDispatcher {
    event CrossChainOrderDispatched(bytes32 indexed orderId);

    /// @notice Dispatch a single cross-chain leg via the SpokePool.
    /// @param order ERC-7683 OnchainCrossChainOrder envelope containing a DispatchOrder in orderData.
    function dispatch(OnchainCrossChainOrder calldata order) external payable;
}

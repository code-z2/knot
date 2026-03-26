// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {OnchainCrossChainOrder} from "../types/Structs.sol";

/// @title ICrossChainExecutor
/// @notice Dispatches cross-chain orders through the source-chain executor module.
interface ICrossChainExecutor {
    /// @notice Dispatch a single cross-chain leg via the SpokePool.
    /// @param order ERC-7683 OnchainCrossChainOrder envelope containing a DispatchOrder in orderData.
    function dispatch(OnchainCrossChainOrder calldata order) external payable;
}

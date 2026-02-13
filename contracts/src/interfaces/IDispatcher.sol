// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {OnchainCrossChainOrder, SuperIntentData} from "../types/Structs.sol";

/// @title IDispatcher
/// @notice Dispatches cross chain orders to the spoke pool
interface IDispatcher {
    event CrossChainOrderDispatched(bytes32 indexed orderId);

    function executeCrossChainOrder(OnchainCrossChainOrder calldata order, bytes calldata signature) external;

    function isValidIntentSignature(SuperIntentData calldata data, uint32 fillDeadline, bytes calldata signature)
        external
        view
        returns (bytes4);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {ExecutionParams} from "../types/Structs.sol";

/// @title IAccumulatorModule
/// @notice Destination-chain fill tracking and intent execution via ERC-7579 module.
interface IAccumulatorModule {
    event FillAccumulated(
        bytes32 indexed fillId, address indexed inputToken, uint256 amount, uint256 totalReceived, uint256 sumOutput
    );

    /// @notice Across V3 callback — accumulates bridged tokens (no execution).
    function handleV3AcrossMessage(address tokenSent, uint256 amount, address relayer, bytes memory message)
        external
        payable;

    /// @notice Execute an accumulated intent via self-call through the account.
    function executeIntent(ExecutionParams calldata params) external;

    /// @notice Mark an expired fill as stale.
    function markStale(bytes32 fillId) external;
}

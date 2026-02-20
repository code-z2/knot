// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {ExecutionParams} from "../types/Structs.sol";

/// @dev Standard Across V3 message handler interface + two-step execution.
/// See: https://github.com/across-protocol/contracts/blob/master/contracts/interfaces/SpokePoolMessageHandler.sol
interface IAccumulator {
    /// @notice Across V3 callback — accumulates bridged tokens (no execution).
    function handleV3AcrossMessage(address tokenSent, uint256 amount, address relayer, bytes memory message)
        external
        payable;

    /// @notice Execute an accumulated intent with Merkle-verified authorization.
    /// @param params      Execution parameters for the dest chain leg.
    /// @param merkleProof Sibling hashes proving the leaf belongs to the signed root.
    /// @param signature   Signature over `toEthSignedMessageHash(merkleRoot)`.
    function executeIntent(ExecutionParams calldata params, bytes32[] calldata merkleProof, bytes calldata signature)
        external;

    /// @notice Sweep unreserved token balance back to the owner.
    function sweep(address token) external;

    /// @notice Mark an expired fill as stale and refund reserved tokens to the owner.
    /// @param fillId The fill ID to mark as stale.
    function markStale(bytes32 fillId) external;
}

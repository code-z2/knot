// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/// @dev Standard Across V3 message handler interface.
/// Expected to be implemented by any contract that receives messages from the SpokePool.
/// See: https://github.com/across-protocol/contracts/blob/master/contracts/interfaces/SpokePoolMessageHandler.sol
interface IAccumulator {
    function handleV3AcrossMessage(address tokenSent, uint256 amount, address relayer, bytes memory message)
        external
        payable;
    function sweep(address token) external;
}

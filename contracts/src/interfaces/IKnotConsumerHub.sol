// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/// @title IKnotConsumerHub
/// @notice Global event hub for cross-chain intent orchestration.
interface IKnotConsumerHub {
    event IntentRegistered(
        bytes32 indexed fillId,
        address indexed account,
        uint256 indexed destinationChainId,
        uint256 sourceChainId,
        uint32 fillDeadline
    );
    event FillReady(bytes32 indexed fillId, address indexed account, uint256 indexed chainId);
    event IntentExecuted(bytes32 indexed fillId, address indexed account, uint256 indexed chainId);
    event IntentDropped(bytes32 indexed fillId, address indexed account, uint256 indexed chainId);
    event IntentStale(bytes32 indexed fillId, address indexed account, uint256 indexed chainId);

    function registerIntent(address account, bytes32 fillId, uint256 destinationChainId, uint32 fillDeadline) external;

    function reportFillReady(address account, bytes32 fillId) external;
    function reportIntentExecuted(address account, bytes32 fillId) external;
    function reportIntentDropped(address account, bytes32 fillId) external;
    function reportIntentStale(address account, bytes32 fillId) external;
}

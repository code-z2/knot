// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Create2} from "openzeppelin-contracts/utils/Create2.sol";
import {Accumulator} from "./Accumulator.sol";

/// @title AccumulatorFactory
/// @notice Deterministically deploys per-user accumulators with CREATE2.
/// @dev
/// Architecture role:
/// - Each account gets a deterministic accumulator address (CREATE2).
/// - The account includes the deploy call in its destination chain batch.
/// - This guarantees the accumulator exists before any fill arrives.
contract AccumulatorFactory {
    address private immutable TREASURY;

    event AccumulatorDeployed(address indexed userAccount, address accumulator);

    /// @param _treasury Treasury address used by new accumulators.
    constructor(address _treasury) {
        TREASURY = _treasury;
    }

    /// @notice Compute the accumulator address for a user and messenger.
    /// @dev Used off-chain to precompute the destination recipient for bridge fills.
    function computeAddress(address userAccount, address messenger) external view returns (address) {
        bytes32 salt = _hashAddress(userAccount);
        return Create2.computeAddress(salt, keccak256(_getBytecode(userAccount, messenger)), address(this));
    }

    /// @notice Deploy the accumulator for msg.sender using a messenger address.
    /// @dev Should be called on the destination chain before any fill arrives.
    function deploy(address messenger) external returns (address accumulator) {
        address userAccount = msg.sender;
        bytes32 salt = _hashAddress(userAccount);
        accumulator = Create2.deploy(0, salt, _getBytecode(userAccount, messenger));
        emit AccumulatorDeployed(userAccount, accumulator);
    }

    /// @dev Creation bytecode for the accumulator with constructor args.
    function _getBytecode(address salt, address messenger) internal view returns (bytes memory) {
        return abi.encodePacked(type(Accumulator).creationCode, abi.encode(salt, messenger, TREASURY));
    }

    /// @dev Hash helper for CREATE2 salt.
    function _hashAddress(address account) internal pure returns (bytes32 result) {
        assembly ("memory-safe") {
            mstore(0x00, shl(96, account))
            result := keccak256(0x0c, 20)
        }
    }
}

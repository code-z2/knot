// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Create2} from "openzeppelin-contracts/utils/Create2.sol";
import {Accumulator} from "./Accumulator.sol";
import {IAccumulatorFactory} from "./interfaces/IAccumulatorFactory.sol";

/// @title AccumulatorFactory
/// @notice Deterministically deploys per-user accumulators with CREATE2.
/// @dev
/// Architecture role:
/// - Each account gets a deterministic accumulator address (CREATE2).
/// - The account calls deploy() during initialize() to create its accumulator.
/// - This guarantees the accumulator exists before any fill arrives.
contract AccumulatorFactory is IAccumulatorFactory {
    event AccumulatorDeployed(address indexed userAccount, address accumulator);

    /// @notice Compute the accumulator address for a user.
    /// @dev Used off-chain to precompute the destination recipient for bridge fills.
    function computeAddress(address userAccount) external view returns (address) {
        bytes32 salt = _hashAddress(userAccount);
        return Create2.computeAddress(salt, keccak256(_getBytecode(userAccount)), address(this));
    }

    /// @notice Deploy the accumulator for msg.sender using a spoke pool address.
    /// @dev Should be called on the destination chain before any fill arrives.
    function deploy(address spokePool) external returns (address accumulator) {
        address userAccount = msg.sender;
        bytes32 salt = _hashAddress(userAccount);
        accumulator = Create2.deploy(0, salt, _getBytecode(userAccount));

        Accumulator(payable(accumulator)).initialize(spokePool);
        emit AccumulatorDeployed(userAccount, accumulator);
    }

    /// @dev Creation bytecode for the accumulator with constructor args.
    function _getBytecode(address userAccount) internal pure returns (bytes memory) {
        return abi.encodePacked(type(Accumulator).creationCode, abi.encode(userAccount));
    }

    /// @dev Hash helper for CREATE2 salt.
    function _hashAddress(address account) internal pure returns (bytes32 result) {
        assembly ("memory-safe") {
            mstore(0x00, shl(96, account))
            result := keccak256(0x0c, 20)
        }
    }
}

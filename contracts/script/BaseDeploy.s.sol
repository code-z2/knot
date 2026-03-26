// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console2} from "forge-std/Script.sol";

import {AccumulatorModule} from "../src/AccumulatorModule.sol";
import {CrossChainExecutor} from "../src/CrossChainExecutor.sol";
import {KnotAccount} from "../src/KnotAccount.sol";
import {KnotConsumerHub} from "../src/KnotConsumerHub.sol";
import {MerkleValidator} from "../src/MerkleValidator.sol";

interface ICreateX {
    function deployCreate2(bytes32 salt, bytes calldata initCode) external payable returns (address deployed);
}

/// @title BaseDeploy
/// @notice Shared deployment flow for Knot V2 singleton contracts.
///
/// @dev The deployed graph is:
///      - MerkleValidator
///      - CrossChainExecutor
///      - AccumulatorModule
///      - KnotConsumerHub(executor, accumulator)
///      - KnotAccount implementation
///
///      Account-specific config such as `spokePool` and `consumerHub` is installed later during
///      account initialization. The deployment scripts intentionally stop at singleton deployment
///      and use CreateX so singleton addresses stay stable across chains.
abstract contract BaseDeploy is Script {
    struct Deployment {
        address validator;
        address executor;
        address accumulator;
        address hub;
        address accountImplementation;
    }

    address internal constant CREATEX = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    bytes32 internal constant VALIDATOR_SALT = keccak256("knot.v2.merkle-validator");
    bytes32 internal constant EXECUTOR_SALT = keccak256("knot.v2.cross-chain-executor");
    bytes32 internal constant ACCUMULATOR_SALT = keccak256("knot.v2.accumulator-module");
    bytes32 internal constant HUB_SALT = keccak256("knot.v2.consumer-hub");
    bytes32 internal constant ACCOUNT_SALT = keccak256("knot.v2.account-implementation");

    error CreateXUnavailable(address createX);
    error CreateXDeployFailed(bytes32 salt);

    /// @dev Broadcasts the singleton deployment set and persists a machine-readable manifest.
    function _deploy(string memory profile) internal returns (Deployment memory deployment) {
        uint256 broadcasterKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(broadcasterKey);

        if (CREATEX.code.length == 0) {
            revert CreateXUnavailable(CREATEX);
        }

        address validator = _deployCreate2(VALIDATOR_SALT, type(MerkleValidator).creationCode);
        address executor = _deployCreate2(EXECUTOR_SALT, type(CrossChainExecutor).creationCode);
        address accumulator = _deployCreate2(ACCUMULATOR_SALT, type(AccumulatorModule).creationCode);
        address hub = _deployCreate2(
            HUB_SALT, abi.encodePacked(type(KnotConsumerHub).creationCode, abi.encode(executor, accumulator))
        );
        address accountImplementation = _deployCreate2(ACCOUNT_SALT, type(KnotAccount).creationCode);

        vm.stopBroadcast();

        deployment = Deployment({
            validator: validator,
            executor: executor,
            accumulator: accumulator,
            hub: hub,
            accountImplementation: accountImplementation
        });

        _writeDeployment(profile, deployment);
        _logDeployment(profile, deployment);
    }

    /// @dev Writes the deployment manifest to `deployments/<profile>/<chainId>.json`.
    function _writeDeployment(string memory profile, Deployment memory deployment) internal {
        string memory root = vm.projectRoot();
        string memory dir = string.concat(root, "/deployments/", profile);
        vm.createDir(dir, true);

        string memory obj = "deployment";
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeString(obj, "network", _networkName(block.chainid));
        vm.serializeAddress(obj, "validator", deployment.validator);
        vm.serializeAddress(obj, "executor", deployment.executor);
        vm.serializeAddress(obj, "accumulator", deployment.accumulator);
        vm.serializeAddress(obj, "hub", deployment.hub);
        string memory json =
            vm.serializeAddress(obj, "accountImplementation", deployment.accountImplementation);

        string memory path = string.concat(dir, "/", vm.toString(block.chainid), ".json");
        vm.writeJson(json, path);
    }

    /// @dev Emits the deployed addresses in a stable, readable format for operators.
    function _logDeployment(string memory profile, Deployment memory deployment) internal view {
        console2.log("Knot deployment complete");
        console2.log("Profile:", profile);
        console2.log("Chain ID:", block.chainid);
        console2.log("Network:", _networkName(block.chainid));
        console2.log("CreateX:", CREATEX);
        console2.log("MerkleValidator:", deployment.validator);
        console2.log("CrossChainExecutor:", deployment.executor);
        console2.log("AccumulatorModule:", deployment.accumulator);
        console2.log("KnotConsumerHub:", deployment.hub);
        console2.log("KnotAccount implementation:", deployment.accountImplementation);
    }

    /// @dev Human-readable labels for the supported deployment targets in the Makefile.
    function _networkName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 11155111) {
            return "sepolia";
        }
        if (chainId == 84532) {
            return "base-sepolia";
        }
        if (chainId == 421614) {
            return "arbitrum-sepolia";
        }
        if (chainId == 42161) {
            return "arbitrum";
        }
        if (chainId == 8453) {
            return "base";
        }
        if (chainId == 137) {
            return "polygon";
        }
        return "unknown";
    }

    /// @dev Deploys one singleton through CreateX, or reuses the address if the bytecode exists.
    function _deployCreate2(bytes32 salt, bytes memory initCode) internal returns (address deployed) {
        deployed = _computeCreate2Address(salt, initCode);
        if (deployed.code.length != 0) {
            return deployed;
        }

        deployed = ICreateX(CREATEX).deployCreate2(salt, initCode);
        if (deployed == address(0)) {
            revert CreateXDeployFailed(salt);
        }
    }

    /// @dev Predicts the Create2 address for `CreateX.deployCreate2(bytes32,bytes)`.
    function _computeCreate2Address(bytes32 salt, bytes memory initCode) internal pure returns (address predicted) {
        predicted = address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATEX, salt, keccak256(initCode))))
            )
        );
    }
}

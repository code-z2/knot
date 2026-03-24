// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {AccumulatorFactory} from "../src/AccumulatorFactory.sol";
import {UnifiedAccount} from "../src/UnifiedAccount.sol";

interface ICreateX {
    function deployCreate2(bytes32 salt, bytes memory initCode) external payable returns (address);
    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash) external view returns (address);
}

/// @title DeployTestnet
/// @notice Deploys AccumulatorFactory on LIMITED_TESTNET chains:
///         Sepolia (11155111), Base Sepolia (84532), Arbitrum Sepolia (421614).
/// @dev Run once per chain:
///   forge script script/DeployTestnet.s.sol:DeployTestnet \
///     --rpc-url $SEPOLIA_RPC --broadcast --verify
contract DeployTestnet is Script {
    ICreateX constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    // P256 Generator Point (for valid constructor generic initialization)
    bytes32 constant GX = 0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;
    bytes32 constant GY = 0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;

    function run() external {
        string memory singletonVersion = vm.envString("SINGLETON_VERSION");
        string memory factoryVersion = vm.envString("FACTORY_VERSION");
        bytes32 factorySalt = keccak256(abi.encodePacked("Accumulator", factoryVersion));
        bytes32 singletonSalt = keccak256(abi.encodePacked("UnifiedAccount", singletonVersion));

        console.log("Deploying to chain ID:", block.chainid);

        vm.startBroadcast();

        // 1. Accumulator Factory
        bytes memory factoryInitCode = type(AccumulatorFactory).creationCode;
        try CREATEX.deployCreate2(factorySalt, factoryInitCode) returns (address factory) {
            console.log("AccumulatorFactory deployed at:", factory);
        } catch Error(string memory reason) {
            console.log("AccumulatorFactory deployment skipped:", reason);
            address factory = CREATEX.computeCreate2Address(factorySalt, keccak256(factoryInitCode));
            assembly {
                let code := extcodesize(factory)
                if eq(code, 0) {
                    revert(0, 0)
                }
            }
            console.log("AccumulatorFactory already deployed at:", factory);
        }

        // 2. Unified Account (Singleton/Implementation)
        bytes memory singletonInitCode = abi.encodePacked(type(UnifiedAccount).creationCode, abi.encode(GX, GY));
        address singleton = CREATEX.deployCreate2(singletonSalt, singletonInitCode);
        console.log("UnifiedAccount deployed at:", singleton);

        vm.stopBroadcast();
    }
}

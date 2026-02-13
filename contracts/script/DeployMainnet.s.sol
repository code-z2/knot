// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {AccumulatorFactory} from "../src/AccumulatorFactory.sol";
import {UnifiedTokenAccount} from "../src/UnifiedTokenAccount.sol";

interface ICreateX {
    function deployCreate2(bytes32 salt, bytes memory initCode) external payable returns (address);
    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash) external view returns (address);
}

/// @title DeployMainnet
/// @notice Deploys AccumulatorFactory on LIMITED_MAINNET chains:
///         Arbitrum (42161), Base (8453), Polygon (137).
/// @dev Run once per chain:
///   forge script script/DeployMainnet.s.sol:DeployMainnet \
///     --rpc-url $ARBITRUM_RPC --broadcast --verify
contract DeployMainnet is Script {
    ICreateX constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
    bytes32 constant ACCUMULATOR_SALT = keccak256("Accumulator_v1");
    bytes32 constant ACCOUNT_SALT = keccak256("UnifiedTokenAccount_v1");

    // P256 Generator Point (for valid constructor generic initialization)
    bytes32 constant GX = 0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;
    bytes32 constant GY = 0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;

    function run() external {
        console.log("Deploying to chain ID:", block.chainid);

        vm.startBroadcast();

        // 1. Accumulator Factory
        bytes memory accInitCode = type(AccumulatorFactory).creationCode;
        address accFactory = CREATEX.deployCreate2(ACCUMULATOR_SALT, accInitCode);
        console.log("AccumulatorFactory deployed at:", accFactory);

        // 2. Unified Token Account (Singleton/Implementation)
        bytes memory accountInitCode = abi.encodePacked(type(UnifiedTokenAccount).creationCode, abi.encode(GX, GY));
        address accountImpl = CREATEX.deployCreate2(ACCOUNT_SALT, accountInitCode);
        console.log("UnifiedTokenAccount deployed at:", accountImpl);

        vm.stopBroadcast();
    }
}

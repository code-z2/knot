// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {AccumulatorFactory} from "../src/AccumulatorFactory.sol";

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
    bytes32 constant SALT = keccak256("Accumulator_v1");

    function run() external {
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        console.log("Deploying to chain ID:", block.chainid);

        bytes memory initCode = abi.encodePacked(type(AccumulatorFactory).creationCode, abi.encode(treasury));

        vm.startBroadcast();

        address deployed = CREATEX.deployCreate2(SALT, initCode);
        console.log("Deployed at:", deployed);

        vm.stopBroadcast();
    }
}

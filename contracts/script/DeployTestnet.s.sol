// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {AccumulatorFactory} from "../src/AccumulatorFactory.sol";

/// @title DeployTestnet
/// @notice Deploys AccumulatorFactory on LIMITED_TESTNET chains:
///         Sepolia (11155111), Base Sepolia (84532), Arbitrum Sepolia (421614).
/// @dev Run once per chain:
///   forge script script/DeployTestnet.s.sol:DeployTestnet \
///     --rpc-url $SEPOLIA_RPC --broadcast --verify
contract DeployTestnet is Script {
    function run() external {
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("Chain ID:", block.chainid);
        console.log("Treasury:", treasury);

        vm.startBroadcast(deployerPrivateKey);
        AccumulatorFactory factory = new AccumulatorFactory(treasury);
        vm.stopBroadcast();

        console.log("AccumulatorFactory deployed at:", address(factory));
    }
}

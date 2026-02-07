// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {AccumulatorFactory} from "../src/AccumulatorFactory.sol";

/// @title DeployMainnet
/// @notice Deploys AccumulatorFactory on LIMITED_MAINNET chains:
///         Arbitrum (42161), Base (8453), Polygon (137).
/// @dev Run once per chain:
///   forge script script/DeployMainnet.s.sol:DeployMainnet \
///     --rpc-url $ARBITRUM_RPC --broadcast --verify
contract DeployMainnet is Script {
    function run() external {
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("Deploying to chain ID:", block.chainid);
        console.log("Treasury:", treasury);

        vm.startBroadcast(deployerPrivateKey);
        AccumulatorFactory factory = new AccumulatorFactory(treasury);
        vm.stopBroadcast();

        console.log("AccumulatorFactory deployed at:", address(factory));
    }
}

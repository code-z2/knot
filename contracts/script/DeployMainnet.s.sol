// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {BaseDeploy} from "./BaseDeploy.s.sol";

/// @title DeployMainnet
/// @notice Deploy Knot V2 singleton contracts for supported mainnet environments.
contract DeployMainnet is BaseDeploy {
    function run() external returns (Deployment memory deployment) {
        return _deploy("mainnet");
    }
}

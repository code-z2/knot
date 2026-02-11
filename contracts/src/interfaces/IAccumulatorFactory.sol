// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

interface IAccumulatorFactory {
    function deploy(address spokePool) external returns (address);
    function computeAddress(address userAccount) external view returns (address);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IStakingConversionFactor {
    function getConversionFactor(address asset) external view returns (uint256 factor, uint256 denomenator);
}

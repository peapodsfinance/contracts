// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IDIAOracleV2 {
    function getValue(string memory key) external view returns (uint128 price, uint128 timestamp);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IRewardsWhitelister {
  function whitelist(address token) external view returns (bool);
}

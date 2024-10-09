// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IRewardsWhitelister {
  event PauseToken(address indexed token, bool isPaused);

  event ToggleToken(address indexed token, bool isWhitelisted);

  function paused(address token) external view returns (bool);

  function whitelist(address token) external view returns (bool);

  function getFullWhitelist() external view returns (address[] memory);
}

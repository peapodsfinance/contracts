// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ILendingAssetVault {
  event PayBackUsedAssets(address indexed user, uint256 amount);

  event UseAssets(address indexed user, uint256 amount);

  function totalAvailableAssets() external view returns (uint256);

  function totalUsed() external view returns (uint256);

  function whitelistWithdraw(uint256 amount) external;
}

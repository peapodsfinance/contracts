// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ILendingAssetVault {
  event DonateAssets(address indexed user, uint256 amount);

  event PayBackUsedAssets(address indexed user, uint256 amount);

  event RedeemFromVault(address indexed vault, uint256 shares, uint256 assets);

  event SetVaultWhitelist(address indexed vault, bool isWhitelisted);

  event SetVaultMaxAlloPercentage(address indexed vault, uint256 percentage);

  event WhitelistDeposit(address indexed user, uint256 amount);

  event WhitelistWithdraw(address indexed user, uint256 amount);

  function totalAvailableAssets() external view returns (uint256);

  function whitelistDeposit(uint256 amount) external;

  function whitelistWithdraw(uint256 amount) external;
}

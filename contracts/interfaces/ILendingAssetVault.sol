// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ILendingAssetVault {
  event DonateAssets(address indexed user, uint256 amount, uint256 newShares);

  event PayBackUsedAssets(address indexed user, uint256 amount);

  event RedeemFromVault(address indexed vault, uint256 shares, uint256 assets);

  event SetMaxVaults(uint8 oldMax, uint8 newMax);

  event SetVaultWhitelist(address indexed vault, bool isWhitelisted);

  event SetVaultMaxAlloPercentage(address indexed vault, uint256 percentage);

  event UpdateAssetMetadataFromVault(address indexed vault);

  event WhitelistDeposit(address indexed user, uint256 amount);

  event WhitelistWithdraw(address indexed user, uint256 amount);

  function vaultUtilization(address vault) external view returns (uint256);

  function totalAssetsUtilized() external view returns (uint256);

  function totalAvailableAssets() external view returns (uint256);

  function totalAvailableAssetsForVault(
    address vault
  ) external view returns (uint256);

  function whitelistUpdate(bool onlyCaller) external;

  function whitelistDeposit(uint256 amount) external;

  function whitelistWithdraw(uint256 amount) external;
}

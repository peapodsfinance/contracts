// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IERC4626Extended is IERC4626 {
    function vaultUtilization(address vault) external view returns (uint256);

    function totalAssetsUtilized() external view returns (uint256);

    function totalAvailableAssets() external view returns (uint256);

    function totalAvailableAssetsForVault(address vault) external view returns (uint256);

    function whitelistUpdate(bool onlyCaller) external;

    function whitelistWithdraw(uint256 amount) external;

    function whitelistDeposit(uint256 amount) external;
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { VaultAccount } from '../libraries/VaultAccount.sol';

interface IFraxlendPair {
  function totalBorrow() external view returns (VaultAccount memory);

  function collateralContract() external view returns (address);

  function userCollateralBalance(address user) external view returns (uint256); // amount of collateral each user is backed

  function userBorrowShares(address user) external view returns (uint256); // represents the shares held by individuals

  function borrowAsset(
    uint256 _borrowAmount,
    uint256 _collateralAmount,
    address _receiver
  ) external returns (uint256 _shares);

  function repayAsset(
    uint256 _shares,
    address _borrower
  ) external returns (uint256 _amountToRepay);

  function removeCollateral(
    uint256 _collateralAmount,
    address _receiver
  ) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import { VaultAccount } from '../libraries/VaultAccount.sol';

interface IFraxlendPair is IERC20 {
  function totalBorrow() external view returns (VaultAccount memory);

  function asset() external view returns (address);

  function collateralContract() external view returns (address);

  function userCollateralBalance(address user) external view returns (uint256); // amount of collateral each user is backed

  function userBorrowShares(address user) external view returns (uint256); // represents the shares held by individuals

  function deposit(
    uint256 _amount,
    address _receiver
  ) external returns (uint256 _sharesReceived);

  function redeem(
    uint256 _shares,
    address _receiver,
    address _owner
  ) external returns (uint256 _amountToReturn);

  function borrowAsset(
    uint256 _borrowAmount,
    uint256 _collateralAmount,
    address _receiver
  ) external returns (uint256 _shares);

  function repayAsset(
    uint256 _shares,
    address _borrower
  ) external returns (uint256 _amountToRepay);

  function addCollateral(uint256 _collateralAmount, address _borrower) external;

  function removeCollateral(
    uint256 _collateralAmount,
    address _receiver
  ) external;
}

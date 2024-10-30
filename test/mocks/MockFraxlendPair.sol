// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IFraxlendPair } from '../../contracts/interfaces/IFraxlendPair.sol';
import { VaultAccount } from '../../contracts/libraries/VaultAccount.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract MockFraxlendPair is IFraxlendPair, ERC20 {
  VaultAccount public _totalBorrow;
  address public _asset;
  address public _collateralContract;
  mapping(address => uint256) public _userCollateralBalance;
  mapping(address => uint256) public _userBorrowShares;

  constructor(
    address asset_,
    address collateralContract_
  ) ERC20('MockFraxlendPair', 'MFP') {
    _asset = asset_;
    _collateralContract = collateralContract_;
  }

  function exchangeRateInfo()
    external
    pure
    returns (ExchangeRateInfo memory _r)
  {
    return _r;
  }

  function totalBorrow() external view override returns (VaultAccount memory) {
    return _totalBorrow;
  }

  function asset() external view override returns (address) {
    return _asset;
  }

  function collateralContract() external view override returns (address) {
    return _collateralContract;
  }

  function userCollateralBalance(
    address user
  ) external view override returns (uint256) {
    return _userCollateralBalance[user];
  }

  function userBorrowShares(
    address user
  ) external view override returns (uint256) {
    return _userBorrowShares[user];
  }

  function convertToAssets(uint256 shares) external view returns (uint256) {
    return (shares * _totalBorrow.amount) / _totalBorrow.shares;
  }

  function addInterest(
    bool _returnAccounting
  ) external override returns (uint256, uint256, uint256, uint64) {
    // Simplified implementation for mock purposes
    uint256 interestAmount = _totalBorrow.amount / 100; // 1% interest
    _totalBorrow.amount += uint128(interestAmount);
    _totalBorrow.shares += uint128(interestAmount); // Simplified 1:1 ratio

    if (_returnAccounting) {
      return (
        interestAmount,
        _totalBorrow.amount,
        _totalBorrow.shares,
        uint64(block.timestamp)
      );
    } else {
      return (0, 0, 0, 0);
    }
  }

  function deposit(
    uint256 _amount,
    address _receiver
  ) external override returns (uint256 _sharesReceived) {
    IERC20(_asset).transferFrom(msg.sender, address(this), _amount);
    _sharesReceived = _amount; // Simplified 1:1 ratio
    _mint(_receiver, _sharesReceived);
    return _sharesReceived;
  }

  function redeem(
    uint256 _shares,
    address _receiver,
    address _owner
  ) external override returns (uint256 _amountToReturn) {
    _amountToReturn = _shares; // Simplified 1:1 ratio
    IERC20(_asset).transfer(_receiver, _amountToReturn);
    _burn(_owner, _shares);
    return _amountToReturn;
  }

  function borrowAsset(
    uint256 _borrowAmount,
    uint256 _collateralAmount,
    address _receiver
  ) external override returns (uint256 _shares) {
    _shares = _borrowAmount; // Simplified 1:1 ratio
    _userBorrowShares[_receiver] += _shares;
    _userCollateralBalance[_receiver] += _collateralAmount;
    _totalBorrow.amount += uint128(_borrowAmount);
    _totalBorrow.shares += uint128(_shares);
    IERC20(_asset).transfer(_receiver, _borrowAmount);
    return _shares;
  }

  function repayAsset(
    uint256 _shares,
    address _borrower
  ) external override returns (uint256 _amountToRepay) {
    _amountToRepay = _shares; // Simplified 1:1 ratio
    IERC20(_asset).transferFrom(msg.sender, address(this), _amountToRepay);
    require(
      _userBorrowShares[_borrower] >= _shares,
      'Insufficient borrow shares'
    );
    _userBorrowShares[_borrower] -= _shares;
    _totalBorrow.amount -= uint128(_amountToRepay);
    _totalBorrow.shares -= uint128(_shares);
    return _amountToRepay;
  }

  function addCollateral(
    uint256 _collateralAmount,
    address _borrower
  ) external override {
    IERC20(_collateralContract).transferFrom(
      msg.sender,
      address(this),
      _collateralAmount
    );
    _userCollateralBalance[_borrower] += _collateralAmount;
  }

  function removeCollateral(
    uint256 _collateralAmount,
    address _receiver
  ) external override {
    require(
      _userCollateralBalance[_receiver] >= _collateralAmount,
      'Insufficient collateral'
    );
    _userCollateralBalance[_receiver] -= _collateralAmount;
    IERC20(_collateralContract).transfer(msg.sender, _collateralAmount);
  }
}

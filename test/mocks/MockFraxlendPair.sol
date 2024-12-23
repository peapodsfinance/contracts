// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IFraxlendPair} from "../../contracts/interfaces/IFraxlendPair.sol";
import {VaultAccount, VaultAccountingLibrary} from "../../contracts/libraries/VaultAccount.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockFraxlendPair is IFraxlendPair, ERC20 {
    using VaultAccountingLibrary for VaultAccount;

    VaultAccount public _totalAsset;
    VaultAccount public _totalBorrow;
    address public _asset;
    address public _collateralContract;
    mapping(address => uint256) public _userCollateralBalance;
    mapping(address => uint256) public _userBorrowShares;

    constructor(address asset_, address collateralContract_) ERC20("MockFraxlendPair", "MFP") {
        _asset = asset_;
        _collateralContract = collateralContract_;
    }

    function exchangeRateInfo() external pure returns (ExchangeRateInfo memory _r) {
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

    function userCollateralBalance(address user) external view override returns (uint256) {
        return _userCollateralBalance[user];
    }

    function userBorrowShares(address user) external view override returns (uint256) {
        return _userBorrowShares[user];
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return _totalAsset.toAmount(shares, false);
    }

    function convertToShares(uint256 assets) external view returns (uint256) {
        return _totalAsset.toShares(assets, false);
    }

    function previewAddInterest()
        external
        view
        returns (
            uint256 _interestEarned,
            uint256 _feesAmount,
            uint256 _feesShare,
            CurrentRateInfo memory _newCurrentRateInfo,
            VaultAccount memory __totalAsset,
            VaultAccount memory __totalBorrow
        )
    {
        // Calculate 1% interest on the total borrowed amount
        _interestEarned = _totalBorrow.amount / 100;

        // 10% of interest goes to fees
        _feesAmount = _interestEarned / 10;

        // Calculate fee shares based on current total asset ratio
        _feesShare = _totalAsset.shares == 0 ? _feesAmount : (_feesAmount * _totalAsset.shares) / _totalAsset.amount;

        // Update total asset accounting
        __totalAsset = _totalAsset;
        __totalAsset.amount += uint128(_interestEarned);
        __totalAsset.shares += uint128(_feesShare);

        // Update total borrow accounting
        __totalBorrow = _totalBorrow;
        __totalBorrow.amount += uint128(_interestEarned);

        return (_interestEarned, _feesAmount, _feesShare, _newCurrentRateInfo, __totalAsset, __totalBorrow);
    }

    function addInterest(bool _returnAccounting)
        external
        override
        returns (
            uint256,
            uint256,
            uint256,
            CurrentRateInfo memory _currentRateInfo,
            VaultAccount memory __totalAsset,
            VaultAccount memory __totalBorrow
        )
    {
        // Calculate interest and fees
        (
            uint256 interestEarned,
            uint256 feesAmount,
            uint256 feesShare,
            ,
            VaultAccount memory newTotalAsset,
            VaultAccount memory newTotalBorrow
        ) = this.previewAddInterest();

        // Update state
        _totalAsset = newTotalAsset;
        _totalBorrow = newTotalBorrow;

        if (_returnAccounting) {
            return (interestEarned, feesAmount, feesShare, _currentRateInfo, _totalAsset, _totalBorrow);
        } else {
            return (0, 0, 0, _currentRateInfo, _totalAsset, _totalBorrow);
        }
    }

    function deposit(uint256 _amount, address _receiver) external override returns (uint256 _sharesReceived) {
        IERC20(_asset).transferFrom(msg.sender, address(this), _amount);

        // Calculate shares to mint
        _sharesReceived = _totalAsset.toShares(_amount, false);
        if (_sharesReceived == 0) _sharesReceived = _amount; // Initial deposit case

        // Update total asset tracking
        _totalAsset.amount += uint128(_amount);
        _totalAsset.shares += uint128(_sharesReceived);

        _mint(_receiver, _sharesReceived);
        return _sharesReceived;
    }

    function redeem(uint256 _shares, address _receiver, address _owner)
        external
        override
        returns (uint256 _amountToReturn)
    {
        // Calculate assets to return
        _amountToReturn = _totalAsset.toAmount(_shares, false);

        // Update total asset tracking
        _totalAsset.amount -= uint128(_amountToReturn);
        _totalAsset.shares -= uint128(_shares);

        IERC20(_asset).transfer(_receiver, _amountToReturn);
        _burn(_owner, _shares);
        return _amountToReturn;
    }

    function borrowAsset(uint256 _borrowAmount, uint256 _collateralAmount, address _receiver)
        external
        override
        returns (uint256 _shares)
    {
        // Calculate borrow shares
        _shares = _totalBorrow.shares == 0 ? _borrowAmount : (_borrowAmount * _totalBorrow.shares) / _totalBorrow.amount;
        if (_shares == 0) _shares = _borrowAmount;

        _userBorrowShares[_receiver] += _shares;
        _userCollateralBalance[_receiver] += _collateralAmount;

        // Update total borrow tracking
        _totalBorrow.amount += uint128(_borrowAmount);
        _totalBorrow.shares += uint128(_shares);

        IERC20(_asset).transfer(_receiver, _borrowAmount);
        return _shares;
    }

    function repayAsset(uint256 _shares, address _borrower) external override returns (uint256 _amountToRepay) {
        // Calculate amount to repay based on shares
        _amountToRepay = _totalBorrow.toAmount(_shares, false);

        IERC20(_asset).transferFrom(msg.sender, address(this), _amountToRepay);
        require(_userBorrowShares[_borrower] >= _shares, "Insufficient borrow shares");

        _userBorrowShares[_borrower] -= _shares;

        // Update total borrow tracking
        _totalBorrow.amount -= uint128(_amountToRepay);
        _totalBorrow.shares -= uint128(_shares);

        return _amountToRepay;
    }

    function addCollateral(uint256 _collateralAmount, address _borrower) external override {
        IERC20(_collateralContract).transferFrom(msg.sender, address(this), _collateralAmount);
        _userCollateralBalance[_borrower] += _collateralAmount;
    }

    function removeCollateral(uint256 _collateralAmount, address _receiver) external override {
        require(_userCollateralBalance[_receiver] >= _collateralAmount, "Insufficient collateral");
        _userCollateralBalance[_receiver] -= _collateralAmount;
        IERC20(_collateralContract).transfer(msg.sender, _collateralAmount);
    }
}

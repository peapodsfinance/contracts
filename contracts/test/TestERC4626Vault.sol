// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/ILendingAssetVault.sol";
import "../interfaces/IFraxlendPair.sol";
import {VaultAccount, VaultAccountingLibrary} from "../libraries/VaultAccount.sol";

contract TestERC4626Vault is IERC4626, ERC20, ERC20Permit {
    using SafeERC20 for IERC20;
    using VaultAccountingLibrary for VaultAccount;

    uint256 constant PRECISION = 10 ** 18;

    address immutable _asset;
    VaultAccount internal _totalVaultAccount;
    uint256 internal _lastAccrualTime;
    uint256 internal _unprocessedInterest;
    uint256 internal _interestRate = 1e16; // 1% APR for testing

    constructor(address __asset) ERC20("Test Vault", "tVAULT") ERC20Permit("Test Vault") {
        _asset = __asset;
        _lastAccrualTime = block.timestamp;
    }

    function _calculateInterest() internal view returns (uint256) {
        uint256 timeDelta = block.timestamp - _lastAccrualTime;
        if (timeDelta == 0 || _totalVaultAccount.amount == 0) return 0;

        // Calculate interest: amount * rate * time
        return (_totalVaultAccount.amount * _interestRate * timeDelta) / (365 days * PRECISION);
    }

    // Simulates interest that would be added without actually adding it
    function previewAddInterest()
        external
        view
        returns (
            uint256 interestEarned,
            uint256,
            uint256,
            IFraxlendPair.CurrentRateInfo memory _currentRateInfo,
            VaultAccount memory _totalAsset,
            VaultAccount memory _totalBorrow
        )
    {
        interestEarned = _calculateInterest() + _unprocessedInterest;

        // Create a preview of total assets after interest
        _totalAsset.amount = uint128(_totalVaultAccount.amount + interestEarned);
        _totalAsset.shares = _totalVaultAccount.shares;

        return (interestEarned, 0, 0, _currentRateInfo, _totalAsset, _totalBorrow);
    }

    // Actually adds interest to the vault
    function addInterest(bool)
        external
        returns (
            uint256 interestEarned,
            uint256,
            uint256,
            IFraxlendPair.CurrentRateInfo memory _currentRateInfo,
            VaultAccount memory _totalAsset,
            VaultAccount memory _totalBorrow
        )
    {
        interestEarned = _calculateInterest() + _unprocessedInterest;
        if (interestEarned > 0) {
            _totalVaultAccount.amount += uint128(interestEarned);
            _unprocessedInterest = 0;
            _lastAccrualTime = block.timestamp;
        }

        _totalAsset = _totalVaultAccount;
        return (interestEarned, 0, 0, _currentRateInfo, _totalAsset, _totalBorrow);
    }

    function asset() external view override returns (address) {
        return _asset;
    }

    function totalAssets() public view override returns (uint256) {
        return _totalVaultAccount.amount;
    }

    function convertToShares(uint256 _assets) public view override returns (uint256) {
        return _totalVaultAccount.toShares(_assets, false);
    }

    function convertToAssets(uint256 _shares) public view override returns (uint256) {
        return _totalVaultAccount.toAmount(_shares, false);
    }

    function maxDeposit(address) external pure override returns (uint256 maxAssets) {
        maxAssets = type(uint256).max - 1;
    }

    function previewDeposit(uint256 _assets) external view override returns (uint256) {
        return convertToShares(_assets);
    }

    function deposit(uint256 _assets, address _receiver) external override returns (uint256 _shares) {
        _shares = _deposit(_assets, _receiver, _msgSender());
    }

    function depositFromLendingAssetVault(address _vault, uint256 _amountAssets) external {
        ILendingAssetVault(_vault).whitelistWithdraw(_amountAssets);
        uint256 _newShares = _deposit(_amountAssets, address(this), address(this));
        _transfer(address(this), _vault, _newShares);
    }

    function withdrawToLendingAssetVault(address _vault, uint256 _amountAssets) external {
        uint256 _shares = convertToShares(_amountAssets);
        _transfer(_vault, address(this), _shares);
        IERC20(_asset).approve(_vault, _amountAssets);
        ILendingAssetVault(_vault).whitelistDeposit(_amountAssets);
        _withdraw(_shares, address(this), address(this));
    }

    function _deposit(uint256 _assets, address _receiver, address _owner) internal returns (uint256 _shares) {
        // Calculate shares before updating state
        _shares = convertToShares(_assets);

        // Update vault accounting
        _totalVaultAccount.amount += uint128(_assets);
        _totalVaultAccount.shares += uint128(_shares);

        _mint(_receiver, _shares);
        if (_owner != address(this)) {
            IERC20(_asset).safeTransferFrom(_owner, address(this), _assets);
        }
        emit Deposit(_owner, _receiver, _assets, _shares);
    }

    function maxMint(address) external pure override returns (uint256 maxShares) {
        maxShares = type(uint256).max - 1;
    }

    function previewMint(uint256 _shares) external view override returns (uint256) {
        return convertToAssets(_shares);
    }

    function mint(uint256 _shares, address _receiver) external override returns (uint256 _assets) {
        _assets = convertToAssets(_shares);
        _deposit(_assets, _receiver, _msgSender());
    }

    function maxWithdraw(address _owner) external view override returns (uint256) {
        return convertToAssets(balanceOf(_owner));
    }

    function previewWithdraw(uint256 _assets) external view override returns (uint256) {
        return convertToShares(_assets);
    }

    function withdraw(uint256 _assets, address _receiver, address _owner) external override returns (uint256 _shares) {
        _shares = convertToShares(_assets);
        _withdraw(_shares, _receiver, _owner);
    }

    function maxRedeem(address _owner) external view override returns (uint256) {
        return balanceOf(_owner);
    }

    function previewRedeem(uint256 _shares) external view override returns (uint256) {
        return convertToAssets(_shares);
    }

    function redeem(uint256 _shares, address _receiver, address _owner) external override returns (uint256 _assets) {
        _assets = _withdraw(_shares, _receiver, _owner);
    }

    function _withdraw(uint256 _shares, address _receiver, address _owner) internal returns (uint256 _assets) {
        // Calculate assets before updating state
        _assets = convertToAssets(_shares);

        // Update vault accounting
        _totalVaultAccount.amount -= uint128(_assets);
        _totalVaultAccount.shares -= uint128(_shares);

        _burn(_owner, _shares);
        IERC20(_asset).safeTransfer(_receiver, _assets);
        emit Withdraw(_owner, _receiver, _receiver, _assets, _shares);
    }

    // For testing - simulate interest accrual
    function simulateInterestAccrual(uint256 amount) external {
        _unprocessedInterest += amount;
    }
}

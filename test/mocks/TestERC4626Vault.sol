// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../contracts/interfaces/ILendingAssetVault.sol";
import "../../contracts/interfaces/IFraxlendPair.sol";
import {VaultAccount} from "../../contracts/libraries/VaultAccount.sol";

contract TestERC4626Vault is IERC4626, ERC20, ERC20Permit {
    using SafeERC20 for IERC20;

    uint256 constant PRECISION = 10 ** 18;

    address _asset;

    constructor(address __asset) ERC20("Test Vault", "tVAULT") ERC20Permit("Test Vault") {
        _asset = __asset;
    }

    // Needed for LendingAssetVault
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
    {}

    // Needed for LendingAssetVault
    function addInterest(bool)
        external
        returns (
            uint256,
            uint256,
            uint256,
            IFraxlendPair.CurrentRateInfo memory _currentRateInfo,
            VaultAccount memory _totalAsset,
            VaultAccount memory _totalBorrow
        )
    {}

    function asset() external view override returns (address) {
        return _asset;
    }

    function totalAssets() public view override returns (uint256) {
        return IERC20(_asset).balanceOf(address(this));
    }

    function convertToShares(uint256 _assets) public view override returns (uint256 _shares) {
        _shares = (_assets * PRECISION) / _cbr();
    }

    function convertToAssets(uint256 _shares) public view override returns (uint256 _assets) {
        _assets = (_shares * _cbr()) / PRECISION;
    }

    function maxDeposit(address) external pure override returns (uint256 maxAssets) {
        maxAssets = type(uint256).max - 1;
    }

    function previewDeposit(uint256 _assets) external view override returns (uint256 _shares) {
        _shares = convertToShares(_assets);
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
        _shares = convertToShares(_assets);
        _mint(_receiver, _shares);
        if (_owner != address(this)) {
            IERC20(_asset).safeTransferFrom(_owner, address(this), _assets);
        }
        emit Deposit(_owner, _receiver, _assets, _shares);
    }

    function maxMint(address) external pure override returns (uint256 maxShares) {
        maxShares = type(uint256).max - 1;
    }

    function previewMint(uint256 _shares) external view override returns (uint256 _assets) {
        _assets = convertToAssets(_shares);
    }

    function mint(uint256 _shares, address _receiver) external override returns (uint256 _assets) {
        _assets = convertToAssets(_shares);
        _deposit(_assets, _receiver, _msgSender());
    }

    function maxWithdraw(address _owner) external view override returns (uint256 _maxAssets) {
        _maxAssets = (balanceOf(_owner) * _cbr()) / PRECISION;
    }

    function previewWithdraw(uint256 _assets) external view override returns (uint256 _shares) {
        _shares = convertToShares(_assets);
    }

    function withdraw(uint256 _assets, address _receiver, address) external override returns (uint256 _shares) {
        _shares = convertToShares(_assets);
        _withdraw(_shares, _receiver, _msgSender());
    }

    function maxRedeem(address _owner) external view override returns (uint256 _maxShares) {
        _maxShares = balanceOf(_owner);
    }

    function previewRedeem(uint256 _shares) external view override returns (uint256 _assets) {
        return convertToAssets(_shares);
    }

    function redeem(uint256 _shares, address _receiver, address) external override returns (uint256 _assets) {
        _assets = _withdraw(_shares, _receiver, _msgSender());
    }

    function _withdraw(uint256 _shares, address _receiver, address _owner) internal returns (uint256 _assets) {
        _assets = convertToAssets(_shares);
        _burn(_owner, _shares);
        IERC20(_asset).safeTransfer(_receiver, _assets);
        emit Withdraw(_owner, _receiver, _receiver, _assets, _shares);
    }

    function _cbr() internal view returns (uint256) {
        uint256 _supply = totalSupply();
        return _supply == 0 ? PRECISION : (PRECISION * totalAssets()) / _supply;
    }
}

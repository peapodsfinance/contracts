// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IDecentralizedIndex} from "./interfaces/IDecentralizedIndex.sol";

/**
 * @title PodVaultUtility
 * @notice A utility contract for interacting with pods+vaults
 */
contract PodVaultUtility is ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidVaultAddress();
    error InvalidReceiverAddress();
    error InvalidAssetAmount();
    error InsufficientVaultShares();

    /// @notice Emitted when an asset is bonded into a pod and deposited into a vault
    /// @param _user The address that initiated the bond and deposit
    /// @param _pod The address of the pod
    /// @param _vault The address of the ERC4626 vault
    /// @param _asset The address of the asset that was bonded
    /// @param _assetAmt The amount of asset that was bonded
    /// @param _podTknsReceived The amount of pod tokens received from bonding
    /// @param _vaultSharesReceived The amount of vault shares received from depositing
    event BondAndDeposit(
        address indexed _user,
        address indexed _pod,
        address indexed _vault,
        address _asset,
        uint256 _assetAmt,
        uint256 _podTknsReceived,
        uint256 _vaultSharesReceived
    );

    function bondAndDeposit(address _vault, uint256 _assetAmt, uint256 _minVaultShares)
        external
        nonReentrant
        returns (uint256 _vaultShares)
    {
        return _bondAndDepositTo(_vault, _assetAmt, _minVaultShares, msg.sender);
    }

    function bondAndDepositTo(address _vault, uint256 _assetAmt, uint256 _minVaultShares, address _receiver)
        external
        nonReentrant
        returns (uint256 _vaultShares)
    {
        return _bondAndDepositTo(_vault, _assetAmt, _minVaultShares, _receiver);
    }

    /**
     * @notice Wraps an asset into a pod and deposits the resulting pod tokens into an ERC4626 vault with a specific receiver
     * @param _vault The address of the ERC4626 vault to deposit into
     * @param _assetAmt The amount of asset to bond
     * @param _minVaultShares The minimum amount of vault shares to receive from depositing (slippage protection)
     * @param _receiver The address to receive the vault shares
     * @return _vaultShares The amount of vault shares received
     */
    function _bondAndDepositTo(address _vault, uint256 _assetAmt, uint256 _minVaultShares, address _receiver)
        internal
        returns (uint256 _vaultShares)
    {
        if (_vault == address(0)) revert InvalidVaultAddress();
        if (_receiver == address(0)) revert InvalidReceiverAddress();
        if (_assetAmt == 0) revert InvalidAssetAmount();

        address _pod = IERC4626(_vault).asset();
        IDecentralizedIndex.IndexAssetInfo[] memory _podAssets = IDecentralizedIndex(_pod).getAllAssets();
        address _asset = _podAssets[0].token;

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _assetAmt);
        uint256 _podTknBalanceBefore = IERC20(_pod).balanceOf(address(this));

        IERC20(_asset).safeIncreaseAllowance(_pod, _assetAmt);
        IDecentralizedIndex(_pod).bond(_asset, _assetAmt, 0);
        uint256 _podTknsReceived = IERC20(_pod).balanceOf(address(this)) - _podTknBalanceBefore;

        IERC20(_pod).safeIncreaseAllowance(_vault, _podTknsReceived);
        _vaultShares = IERC4626(_vault).deposit(_podTknsReceived, _receiver);
        if (_vaultShares < _minVaultShares) revert InsufficientVaultShares();

        emit BondAndDeposit(msg.sender, _pod, _vault, _asset, _assetAmt, _podTknsReceived, _vaultShares);
    }
}

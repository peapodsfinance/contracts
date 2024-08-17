// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/interfaces/IERC4626.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './interfaces/ILendingAssetVault.sol';

contract LendingAssetVault is
  IERC4626,
  ILendingAssetVault,
  ERC20,
  ERC20Permit,
  Ownable
{
  using SafeERC20 for IERC20;

  uint256 constant PRECISION = 10 ** 18;

  address _asset;
  uint256 _totalAssets;
  uint256 _totalAssetsUtilized;

  uint256 public lastAssetChange;
  mapping(address => bool) public vaultWhitelist;
  mapping(address => uint256) public vaultUtilization;
  mapping(address => uint256) _vaultMaxPerc;
  mapping(address => uint256) _vaultWhitelistCbr;

  modifier onlyWhitelist() {
    require(vaultWhitelist[_msgSender()], 'WL');
    _;
  }

  constructor(
    string memory _name,
    string memory _symbol,
    address __asset
  ) ERC20(_name, _symbol) ERC20Permit(_name) {
    _asset = __asset;
  }

  function asset() external view override returns (address) {
    return _asset;
  }

  function totalAssets() public view override returns (uint256) {
    return _totalAssets;
  }

  function totalAvailableAssets() public view override returns (uint256) {
    return _totalAssets - _totalAssetsUtilized;
  }

  function convertToShares(
    uint256 _assets
  ) public view override returns (uint256 _shares) {
    _shares = (_assets * PRECISION) / _cbr();
  }

  function convertToAssets(
    uint256 _shares
  ) public view override returns (uint256 _assets) {
    _assets = (_shares * _cbr()) / PRECISION;
  }

  function maxDeposit(
    address
  ) external pure override returns (uint256 maxAssets) {
    maxAssets = type(uint256).max - 1;
  }

  function previewDeposit(
    uint256 _assets
  ) external view override returns (uint256 _shares) {
    _shares = convertToShares(_assets);
  }

  function deposit(
    uint256 _assets,
    address _receiver
  ) external override returns (uint256 _shares) {
    _shares = _deposit(_assets, _receiver);
  }

  function _deposit(
    uint256 _assets,
    address _receiver
  ) internal returns (uint256 _shares) {
    lastAssetChange = block.timestamp;
    _shares = convertToShares(_assets);
    _totalAssets += _assets;
    _mint(_receiver, _shares);
    IERC20(_asset).safeTransferFrom(_msgSender(), address(this), _assets);
    emit Deposit(_msgSender(), _receiver, _assets, _shares);
  }

  function maxMint(address) external pure override returns (uint256 maxShares) {
    maxShares = type(uint256).max - 1;
  }

  function previewMint(
    uint256 _shares
  ) external view override returns (uint256 _assets) {
    _assets = convertToAssets(_shares);
  }

  function mint(
    uint256 _shares,
    address _receiver
  ) external override returns (uint256 _assets) {
    _assets = convertToAssets(_shares);
    _deposit(_assets, _receiver);
  }

  function maxWithdraw(
    address _owner
  ) external view override returns (uint256 _maxAssets) {
    _maxAssets = (balanceOf(_owner) * _cbr()) / PRECISION;
  }

  function previewWithdraw(
    uint256 _assets
  ) external view override returns (uint256 _shares) {
    _shares = convertToShares(_assets);
  }

  function withdraw(
    uint256 _assets,
    address _receiver,
    address
  ) external override returns (uint256 _shares) {
    _shares = convertToShares(_assets);
    _withdraw(_shares, _receiver);
  }

  function maxRedeem(
    address _owner
  ) external view override returns (uint256 _maxShares) {
    _maxShares = balanceOf(_owner);
  }

  function previewRedeem(
    uint256 _shares
  ) external view override returns (uint256 _assets) {
    return convertToAssets(_shares);
  }

  function redeem(
    uint256 _shares,
    address _receiver,
    address
  ) external override returns (uint256 _assets) {
    _assets = _withdraw(_shares, _receiver);
  }

  /// @notice The ```whitelistWithdraw``` is called by any whitelisted vault to withdraw assets.
  /// @param _assetAmt the amount of underlying assets to withdraw
  function whitelistWithdraw(
    uint256 _assetAmt
  ) external override onlyWhitelist {
    address _vault = _msgSender();
    uint256 _newAssetUtil = vaultUtilization[_vault] + _assetAmt;
    require(
      (PRECISION * _newAssetUtil) / _totalAssets <= _vaultMaxPerc[_vault],
      'MAX'
    );
    vaultUtilization[_vault] = _newAssetUtil;
    _totalAssetsUtilized += _assetAmt;
    IERC20(_asset).safeTransfer(_vault, _assetAmt);
    emit WhitelistWithdraw(_vault, _assetAmt);
  }

  /// @notice The ```whitelistDeposit``` is called by any whitelisted target vault to deposit assets back into this vault.
  /// @notice need this instead of direct depositing in order to handle accounting for used assets and validation
  /// @param _assetAmt the amount of underlying assets to deposit
  function whitelistDeposit(uint256 _assetAmt) external override onlyWhitelist {
    address _vault = _msgSender();
    uint256 _prevRatio = _vaultWhitelistCbr[_vault];
    _vaultWhitelistCbr[_vault] = IERC4626(_vault).convertToAssets(PRECISION);

    // calculate the current ratio of assets in the target vault to previously recorded ratio
    // to correctly calculate the change in total assets here based on how the vault share
    // has changed over time
    uint256 _vaultAssetRatio = _prevRatio == 0
      ? 0
      : _prevRatio > _vaultWhitelistCbr[_vault]
        ? ((PRECISION * _prevRatio) / _vaultWhitelistCbr[_vault]) -
          _vaultWhitelistCbr[_vault]
        : ((PRECISION * _vaultWhitelistCbr[_vault]) / _prevRatio) - _prevRatio;
    _totalAssets = _vaultWhitelistCbr[_vault] > _prevRatio
      ? _totalAssets + ((_assetAmt * _vaultAssetRatio) / PRECISION)
      : _totalAssets - ((_assetAmt * _vaultAssetRatio) / PRECISION);
    _totalAssetsUtilized -= _assetAmt > _totalAssetsUtilized
      ? _totalAssetsUtilized
      : _assetAmt;
    vaultUtilization[_vault] -= _assetAmt > vaultUtilization[_vault]
      ? vaultUtilization[_vault]
      : _assetAmt;
    IERC20(_asset).safeTransferFrom(_vault, address(this), _assetAmt);
    emit WhitelistDeposit(_vault, _assetAmt);
  }

  function _withdraw(
    uint256 _shares,
    address _receiver
  ) internal returns (uint256 _assets) {
    lastAssetChange = block.timestamp;
    _assets = convertToAssets(_shares);
    _burn(_msgSender(), _shares);
    IERC20(_asset).safeTransfer(_receiver, _assets);
    _totalAssets -= _assets;
    emit Withdraw(_msgSender(), _receiver, _receiver, _assets, _shares);
  }

  /// @notice Assumes underlying vault asset has decimals == 18
  function _cbr() internal view returns (uint256) {
    uint256 _supply = totalSupply();
    return _supply == 0 ? PRECISION : (PRECISION * _totalAssets) / _supply;
  }

  function _assetDecimals() internal view returns (uint8) {
    return IERC20Metadata(_asset).decimals();
  }

  function setVaultWhitelist(address _vault, bool _allowed) external onlyOwner {
    require(vaultWhitelist[_vault] != _allowed, 'T');
    vaultWhitelist[_vault] = _allowed;
    emit SetVaultWhitelist(_vault, _allowed);
  }

  /// @notice The ```setVaultMaxPerc``` sets the maximum amount of vault assets allowed to be allocated to a whitelisted vault
  /// @param _vault the vault we're allocating to
  /// @param _percentage the percentage, up to PRECISION (100%), of assets we can allocate to this vault
  function setVaultMaxPerc(
    address _vault,
    uint256 _percentage
  ) external onlyOwner {
    require(_percentage <= PRECISION, 'MAX');
    _vaultMaxPerc[_vault] = _percentage;
    emit SetVaultMaxAlloPercentage(_vault, _percentage);
  }
}

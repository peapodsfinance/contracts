// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/interfaces/IERC4626.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './interfaces/ILendingAssetVault.sol';

interface IVaultInterestUpdate {
  function addInterest() external;
}

contract LendingAssetVault is
  IERC4626,
  ILendingAssetVault,
  ERC20,
  ERC20Permit,
  Ownable
{
  using SafeERC20 for IERC20;

  uint16 constant PERCENTAGE_PRECISION = 10000;
  uint256 constant PRECISION = 10 ** 27;

  address _asset;
  uint256 _totalAssets;
  uint256 _totalAssetsUtilized;
  bool _updateInterestOnVaults = true;

  uint8 public maxVaults = 12;
  uint256 public lastAssetChange;
  mapping(address => bool) public vaultWhitelist;
  mapping(address => uint256) public override vaultUtilization;
  mapping(address => uint256) _vaultMaxPerc;
  mapping(address => uint256) _vaultWhitelistCbr;

  address[] _vaultWhitelistAry;
  // vault address => idx in _vaultWhitelistAry
  mapping(address => uint256) _vaultWhitelistAryIdx;

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

  function totalAssetsUtilized() public view override returns (uint256) {
    return _totalAssetsUtilized;
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
    _updateInterestAndMdInAllVaults();
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

  function donate(uint256 _assetAmt) external {
    _deposit(_assetAmt, address(this));
    _burn(address(this), convertToShares(_assetAmt));
    emit DonateAssets(_msgSender(), _assetAmt);
  }

  function _withdraw(
    uint256 _shares,
    address _receiver
  ) internal returns (uint256 _assets) {
    _updateInterestAndMdInAllVaults();
    lastAssetChange = block.timestamp;
    _assets = convertToAssets(_shares);
    require(totalAvailableAssets() >= _assets, 'AV');
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

  function _updateInterestAndMdInAllVaults() internal {
    if (!_updateInterestOnVaults) {
      return;
    }
    for (uint256 _i; _i < _vaultWhitelistAry.length; _i++) {
      address _vault = _vaultWhitelistAry[_i];
      IVaultInterestUpdate(_vault).addInterest();
      _updateAssetMetadataFromVault(_vault);
    }
  }

  function whitelistUpdate() external override onlyWhitelist {
    _updateAssetMetadataFromVault(_msgSender());
  }

  /// @notice The ```whitelistWithdraw``` is called by any whitelisted vault to withdraw assets.
  /// @param _assetAmt the amount of underlying assets to withdraw
  function whitelistWithdraw(
    uint256 _assetAmt
  ) external override onlyWhitelist {
    address _vault = _msgSender();
    _updateAssetMetadataFromVault(_vault);

    // validate that our new vault utilization does not exceed our max. Since we
    // call this after updating _totalAssets above it reflects the latest total,
    // but this is okay since we should validate total utilization after we account
    // for changes from this vault anyways
    require(
      (PERCENTAGE_PRECISION * (vaultUtilization[_vault] + _assetAmt)) /
        _totalAssets <=
        _vaultMaxPerc[_vault],
      'MAX'
    );
    vaultUtilization[_vault] += _assetAmt;
    _totalAssetsUtilized += _assetAmt;
    IERC20(_asset).safeTransfer(_vault, _assetAmt);
    emit WhitelistWithdraw(_vault, _assetAmt);
  }

  /// @notice The ```whitelistDeposit``` is called by any whitelisted target vault to deposit assets back into this vault.
  /// @notice need this instead of direct depositing in order to handle accounting for used assets and validation
  /// @param _assetAmt the amount of underlying assets to deposit
  function whitelistDeposit(uint256 _assetAmt) external override onlyWhitelist {
    address _vault = _msgSender();
    _updateAssetMetadataFromVault(_vault);
    vaultUtilization[_vault] -= _assetAmt;
    _totalAssetsUtilized -= _assetAmt;
    IERC20(_asset).safeTransferFrom(_vault, address(this), _assetAmt);
    emit WhitelistDeposit(_vault, _assetAmt);
  }

  /// @notice The ```_updateAssetMetadataFromVault``` updates _totalAssets based on  the current ratio
  /// @notice of assets in the target vault to previously recorded ratio
  /// @notice to correctly calculate the change in total assets here based on how the vault share
  /// @notice has changed over time
  /// @param _vault the vault we're adjusting _totalAssets from based on it's CBR updates from last check
  function _updateAssetMetadataFromVault(address _vault) internal {
    uint256 _prevVaultCbr = _vaultWhitelistCbr[_vault];
    _vaultWhitelistCbr[_vault] = IERC4626(_vault).convertToAssets(PRECISION);
    if (_prevVaultCbr == 0) {
      return;
    }
    uint256 _vaultAssetRatioChange = _prevVaultCbr > _vaultWhitelistCbr[_vault]
      ? ((PRECISION * _prevVaultCbr) / _vaultWhitelistCbr[_vault]) - PRECISION
      : ((PRECISION * _vaultWhitelistCbr[_vault]) / _prevVaultCbr) - PRECISION;

    uint256 _currentAssetsUtilized = vaultUtilization[_vault];
    vaultUtilization[_vault] = _prevVaultCbr > _vaultWhitelistCbr[_vault]
      ? _currentAssetsUtilized -
        (_currentAssetsUtilized * _vaultAssetRatioChange) /
        PRECISION
      : _currentAssetsUtilized +
        (_currentAssetsUtilized * _vaultAssetRatioChange) /
        PRECISION;
    _totalAssetsUtilized =
      _totalAssetsUtilized -
      _currentAssetsUtilized +
      vaultUtilization[_vault];
    _totalAssets =
      _totalAssets -
      _currentAssetsUtilized +
      vaultUtilization[_vault];
  }

  function redeemFromVault(address _vault, uint256 _amountShares) external {
    _updateAssetMetadataFromVault(_vault);
    _amountShares = _amountShares == 0
      ? IERC20(_vault).balanceOf(address(this))
      : _amountShares;
    uint256 _amountAssets = IERC4626(_vault).redeem(
      _amountShares,
      address(this),
      address(this)
    );
    vaultUtilization[_vault] -= _amountAssets;
    _totalAssetsUtilized -= _amountAssets;
    emit RedeemFromVault(_vault, _amountShares, _amountAssets);
  }

  function setMaxVaults(uint8 _newMax) external onlyOwner {
    require(_newMax <= 20, 'M');
    maxVaults = _newMax;
  }

  function setUpdateInterestOnVaults(bool _exec) external onlyOwner {
    require(_updateInterestOnVaults != _exec, 'T');
    _updateInterestOnVaults = _exec;
  }

  function setVaultWhitelist(address _vault, bool _allowed) external onlyOwner {
    require(vaultWhitelist[_vault] != _allowed, 'T');
    vaultWhitelist[_vault] = _allowed;
    if (_allowed) {
      require(_vaultWhitelistAry.length <= maxVaults, 'M');
      _vaultWhitelistAryIdx[_vault] = _vaultWhitelistAry.length;
      _vaultWhitelistAry.push(_vault);
    } else {
      uint256 _idx = _vaultWhitelistAryIdx[_vault];
      address _movingVault = _vaultWhitelistAry[_vaultWhitelistAry.length - 1];
      _vaultWhitelistAry[_idx] = _movingVault;
      _vaultWhitelistAryIdx[_movingVault] = _idx;
      _vaultWhitelistAry.pop();
    }
    emit SetVaultWhitelist(_vault, _allowed);
  }

  /// @notice The ```setVaultMaxPerc``` sets the maximum amount of vault assets allowed to be allocated to a whitelisted vault
  /// @param _vault the vault we're allocating to
  /// @param _percentage the percentage, up to PERCENTAGE_PRECISION (100%), of assets we can allocate to this vault
  function setVaultMaxPerc(
    address _vault,
    uint256 _percentage
  ) external onlyOwner {
    require(_percentage <= PERCENTAGE_PRECISION, 'MAX');
    _vaultMaxPerc[_vault] = _percentage;
    emit SetVaultMaxAlloPercentage(_vault, _percentage);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/interfaces/IERC4626.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './interfaces/ILendingAssetVault.sol';
import 'forge-std/console.sol';

interface IVaultInterestUpdate {
  function addInterest(
    bool
  ) external returns (uint256, uint256, uint256, uint64);
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

  address immutable _asset;
  uint256 _totalAssets;
  uint256 _totalAssetsUtilized;

  uint8 public maxVaults = 12;
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

  function totalAvailableAssetsForVault(
    address _vault
  ) public view override returns (uint256 _totalVaultAvailable) {
    uint256 _overallAvailable = totalAvailableAssets();

    uint256 _vaultMax = ((_totalAssets * _vaultMaxPerc[_vault]) /
      PERCENTAGE_PRECISION);

    _totalVaultAvailable = _vaultMax > vaultUtilization[_vault]
      ? _vaultMax - vaultUtilization[_vault]
      : 0;

    _totalVaultAvailable = _overallAvailable < _totalVaultAvailable
      ? _overallAvailable
      : _totalVaultAvailable;
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
    maxAssets = type(uint256).max;
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

  /// @notice Internal function to handle asset deposits
  /// @param _assets The amount of assets to deposit
  /// @param _receiver The address that will receive the shares
  /// @return _shares The amount of shares minted
  function _deposit(
    uint256 _assets,
    address _receiver
  ) internal returns (uint256 _shares) {
    require(_assets != 0, 'M');

    _updateInterestAndMdInAllVaults(address(0));
    _shares = convertToShares(_assets);
    require(_shares != 0, 'MS');
    _totalAssets += _assets;
    _mint(_receiver, _shares);
    IERC20(_asset).safeTransferFrom(_msgSender(), address(this), _assets);
    emit Deposit(_msgSender(), _receiver, _assets, _shares);
  }

  function maxMint(address) external pure override returns (uint256 maxShares) {
    maxShares = type(uint256).max;
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
    uint256 _totalAvailable = totalAvailableAssets();
    uint256 _ownerMax = (balanceOf(_owner) * _cbr()) / PRECISION;
    _maxAssets = _ownerMax > _totalAvailable ? _totalAvailable : _ownerMax;
  }

  function previewWithdraw(
    uint256 _assets
  ) external view override returns (uint256 _shares) {
    _shares = convertToShares(_assets);
  }

  function withdraw(
    uint256 _assets,
    address _receiver,
    address _owner
  ) external override returns (uint256 _shares) {
    _updateInterestAndMdInAllVaults(address(0));
    _shares = convertToShares(_assets);
    _withdraw(_shares, _assets, _owner, _msgSender(), _receiver);
  }

  function maxRedeem(
    address _owner
  ) external view override returns (uint256 _maxShares) {
    uint256 _totalAvailableShares = convertToShares(totalAvailableAssets());
    uint256 _ownerMax = balanceOf(_owner);
    _maxShares = _ownerMax > _totalAvailableShares
      ? _totalAvailableShares
      : _ownerMax;
  }

  function previewRedeem(
    uint256 _shares
  ) external view override returns (uint256 _assets) {
    return convertToAssets(_shares);
  }

  function redeem(
    uint256 _shares,
    address _receiver,
    address _owner
  ) external override returns (uint256 _assets) {
    _updateInterestAndMdInAllVaults(address(0));
    _assets = convertToAssets(_shares);
    _withdraw(_shares, _assets, _owner, _msgSender(), _receiver);
  }

  /// @notice Donate assets to the vault without receiving shares
  /// @param _assetAmt The amount of assets to donate
  function donate(uint256 _assetAmt) external {
    uint256 _newShares = _deposit(_assetAmt, address(this));
    _burn(address(this), _newShares);
    emit DonateAssets(_msgSender(), _assetAmt, _newShares);
  }

  /// @notice Internal function to handle share withdrawals
  /// @param _shares The amount of shares to withdraw
  /// @param _assets The amount of assets to withdraw
  /// @param _owner The owner of the shares being withdrawn
  /// @param _caller The address who initiated withdrawing
  /// @param _receiver The address that will receive the assets
  function _withdraw(
    uint256 _shares,
    uint256 _assets,
    address _owner,
    address _caller,
    address _receiver
  ) internal {
    if (_caller != _owner) {
      _spendAllowance(_owner, _caller, _shares);
    }
    uint256 _totalAvailable = totalAvailableAssets();
    _totalAssets -= _assets;

    require(_totalAvailable >= _assets, 'AV');
    _burn(_owner, _shares);
    IERC20(_asset).safeTransfer(_receiver, _assets);
    emit Withdraw(_owner, _receiver, _receiver, _assets, _shares);
  }

  /// @notice Assumes underlying vault asset has decimals == 18
  function _cbr() internal view returns (uint256) {
    uint256 _supply = totalSupply();
    return _supply == 0 ? PRECISION : (PRECISION * _totalAssets) / _supply;
  }

  /// @notice Updates interest and metadata for all whitelisted vaults
  /// @param _vaultToExclude Address of the vault to exclude from the update
  function _updateInterestAndMdInAllVaults(address _vaultToExclude) internal {
    uint256 _l = _vaultWhitelistAry.length;
    for (uint256 _i; _i < _l; _i++) {
      address _vault = _vaultWhitelistAry[_i];
      if (_vault == _vaultToExclude) {
        continue;
      }
      IVaultInterestUpdate(_vault).addInterest(false);
      _updateAssetMetadataFromVault(_vault);
    }
  }

  /// @notice The ```whitelistUpdate``` function updates metadata for all vaults
  /// @param _onlyCaller If true, only update the caller's vault metadata
  function whitelistUpdate(bool _onlyCaller) external override onlyWhitelist {
    if (_onlyCaller) {
      _updateAssetMetadataFromVault(_msgSender());
    } else {
      _updateInterestAndMdInAllVaults(_msgSender());
    }
  }

  /// @notice The ```whitelistWithdraw``` function is called by any whitelisted vault to withdraw assets.
  /// @param _assetAmt the amount of underlying assets to withdraw
  function whitelistWithdraw(
    uint256 _assetAmt
  ) external override onlyWhitelist {
    address _vault = _msgSender();
    _updateAssetMetadataFromVault(_vault);

    // validate max after doing vault accounting above
    require(totalAvailableAssetsForVault(_vault) >= _assetAmt, 'MAX');
    vaultUtilization[_vault] += _assetAmt;
    _totalAssetsUtilized += _assetAmt;
    IERC20(_asset).safeTransfer(_vault, _assetAmt);
    emit WhitelistWithdraw(_vault, _assetAmt);
  }

  /// @notice The ```whitelistDeposit``` function is called by any whitelisted target vault to deposit assets back into this vault.
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

  /// @notice The ```_updateAssetMetadataFromVault``` function updates _totalAssets based on  the current ratio
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
    uint256 _changeUtilizedState = (_currentAssetsUtilized *
      _vaultAssetRatioChange) / PRECISION;
    vaultUtilization[_vault] = _prevVaultCbr > _vaultWhitelistCbr[_vault]
      ? _currentAssetsUtilized < _changeUtilizedState
        ? _currentAssetsUtilized
        : _currentAssetsUtilized - _changeUtilizedState
      : _currentAssetsUtilized + _changeUtilizedState;
    _totalAssetsUtilized =
      _totalAssetsUtilized -
      _currentAssetsUtilized +
      vaultUtilization[_vault];
    _totalAssets =
      _totalAssets -
      _currentAssetsUtilized +
      vaultUtilization[_vault];
    emit UpdateAssetMetadataFromVault(_vault);
  }

  /// @notice The ```redeemFromVault``` function redeems shares from a specific vault
  /// @param _vault The address of the vault to redeem from
  /// @param _amountShares The amount of shares to redeem (0 for all)
  function redeemFromVault(
    address _vault,
    uint256 _amountShares
  ) external onlyOwner {
    _updateAssetMetadataFromVault(_vault);
    _amountShares = _amountShares == 0
      ? IERC20(_vault).balanceOf(address(this))
      : _amountShares;
    uint256 _amountAssets = IERC4626(_vault).redeem(
      _amountShares,
      address(this),
      address(this)
    );
    uint256 _redeemAmt = vaultUtilization[_vault] < _amountAssets
      ? vaultUtilization[_vault]
      : _amountAssets;
    vaultUtilization[_vault] -= _redeemAmt;
    _totalAssetsUtilized -= _redeemAmt;
    emit RedeemFromVault(_vault, _amountShares, _redeemAmt);
  }

  /// @notice Set the maximum number of vaults allowed
  /// @param _newMax The new maximum number of vaults (must be <= 20)
  function setMaxVaults(uint8 _newMax) external onlyOwner {
    require(_newMax <= 20, 'M');
    uint8 _oldMax = maxVaults;
    maxVaults = _newMax;
    emit SetMaxVaults(_oldMax, _newMax);
  }

  /// @notice Add or remove a vault from the whitelist
  /// @param _vault The address of the vault to update
  /// @param _allowed True to add to whitelist, false to remove
  function setVaultWhitelist(address _vault, bool _allowed) external onlyOwner {
    require(vaultWhitelist[_vault] != _allowed, 'T');
    vaultWhitelist[_vault] = _allowed;
    if (_allowed) {
      require(_vaultWhitelistAry.length < maxVaults, 'M');
      _vaultWhitelistAryIdx[_vault] = _vaultWhitelistAry.length;
      _vaultWhitelistAry.push(_vault);
    } else {
      uint256 _idx = _vaultWhitelistAryIdx[_vault];
      address _movingVault = _vaultWhitelistAry[_vaultWhitelistAry.length - 1];
      _vaultWhitelistAry[_idx] = _movingVault;
      _vaultWhitelistAryIdx[_movingVault] = _idx;

      // clean up state
      _vaultWhitelistAry.pop();
      delete _vaultMaxPerc[_vault];
      delete _vaultWhitelistAryIdx[_vault];
    }
    emit SetVaultWhitelist(_vault, _allowed);
  }

  /// @notice The ```setVaultMaxPerc``` function sets the maximum amount of vault assets allowed to be allocated to a whitelisted vault
  /// @param _vaults the vaults we're allocating to
  /// @param _percentage the percentages, up to PERCENTAGE_PRECISION (100%), of assets we can allocate to these vaults
  function setVaultMaxPerc(
    address[] memory _vaults,
    uint256[] memory _percentage
  ) external onlyOwner {
    require(_vaults.length == _percentage.length, 'SL');
    _updateInterestAndMdInAllVaults(address(0));
    for (uint256 _i; _i < _vaults.length; _i++) {
      address _vault = _vaults[_i];
      uint256 _perc = _percentage[_i];
      require(_perc <= PERCENTAGE_PRECISION, 'MAX');
      _vaultMaxPerc[_vault] = _perc;
      emit SetVaultMaxAlloPercentage(_vault, _perc);
    }
  }
}

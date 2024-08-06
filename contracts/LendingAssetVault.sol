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
  uint256 _totalUsed;

  mapping(address => bool) public useWhitelist;

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

  function totalUsed() external view override returns (uint256) {
    return _totalUsed;
  }

  function totalAvailableAssets() public view override returns (uint256) {
    return _totalAssets - _totalUsed;
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

  /// @notice The ```whitelistWithdraw``` is called by any whitelisted account to withdraw assets.
  /// @param _amount the amount of underlying assets to withdraw
  function whitelistWithdraw(uint256 _amount) external {
    require(useWhitelist[_msgSender()], 'A');
    _totalUsed += _amount;
    IERC20(_asset).safeTransfer(_msgSender(), _amount);
    emit UseAssets(_msgSender(), _amount);
  }

  function _withdraw(
    uint256 _shares,
    address _receiver
  ) internal returns (uint256 _assets) {
    _assets = convertToAssets(_shares);
    _burn(_msgSender(), _shares);
    IERC20(_asset).safeTransfer(_receiver, _assets);
    _totalAssets -= _assets;
    emit Withdraw(_msgSender(), _receiver, _receiver, _assets, _shares);
  }

  // @notice: assumes underlying vault asset has decimals == 18
  function _cbr() internal view returns (uint256) {
    uint256 _supply = totalSupply();
    return _supply == 0 ? PRECISION : (PRECISION * totalAssets()) / _supply;
  }

  function _assetDecimals() internal view returns (uint8) {
    return IERC20Metadata(_asset).decimals();
  }

  function setWhitelist(address _wallet, bool _isAllowed) external onlyOwner {
    require(useWhitelist[_wallet] != _isAllowed, 'T');
    useWhitelist[_wallet] = _isAllowed;
  }
}

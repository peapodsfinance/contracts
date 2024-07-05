// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '../interfaces/IVotingPool.sol';
import '../TokenRewards.sol';

contract VotingPool is IVotingPool, ERC20, Ownable {
  using SafeERC20 for IERC20;

  address public immutable override REWARDS;
  uint256 public override lockupPeriod = 7 days;

  // asset contract => Asset
  mapping(address => Asset) public assets;
  // user => asset => State
  mapping(address => mapping(address => Stake)) public stakes;

  constructor(
    address _pairedLpToken,
    address _rewardsToken,
    IProtocolFeeRouter _feeRouter,
    IRewardsWhitelister _rewardsWhitelist,
    IDexAdapter _dexHandler,
    IV3TwapUtilities _v3TwapUtilities
  ) ERC20('Peapods Voting', 'vlPEAS') {
    REWARDS = address(
      new TokenRewards(
        _feeRouter,
        _rewardsWhitelist,
        _dexHandler,
        _v3TwapUtilities,
        address(this),
        _pairedLpToken,
        address(this),
        _rewardsToken
      )
    );
  }

  function processPreSwapFeesAndSwap() external override {
    // NOOP
  }

  function stake(address _asset, uint256 _amount) external override {
    require(_amount > 0, 'A');
    require(assets[_asset].enabled, 'E');

    IERC20(_asset).safeTransferFrom(_msgSender(), address(this), _amount);

    uint256 _convFctr = 1;
    uint256 _convDenom = 1;
    if (address(assets[_asset].convFactor) != address(0)) {
      (_convFctr, _convDenom) = assets[_asset].convFactor.getConversionFactor(
        _asset
      );
    }

    Stake storage _stake = stakes[_msgSender()][_asset];
    _stake.lastStaked = block.timestamp;
    uint256 _mintedAmtBefore = _stake.amtStaked == 0
      ? 0
      : (_stake.amtStaked * _stake.stakedToOutputFactor) /
        _stake.stakedToOutputDenomenator;
    _stake.amtStaked += _amount;
    _stake.stakedToOutputFactor = _convFctr;
    _stake.stakedToOutputDenomenator = _convDenom;
    uint256 _finalNewMintAmt = (_stake.amtStaked * _convFctr) / _convDenom;
    if (_finalNewMintAmt > _mintedAmtBefore) {
      _mint(_msgSender(), _finalNewMintAmt - _mintedAmtBefore);
    } else if (_mintedAmtBefore > _finalNewMintAmt) {
      _burn(_msgSender(), _mintedAmtBefore - _finalNewMintAmt);
    }
    emit AddStake(_msgSender(), _asset, _amount, _convFctr, _convDenom);
  }

  function unstake(address _asset, uint256 _amount) external override {
    require(_amount > 0, 'R');
    Stake storage _stake = stakes[_msgSender()][_asset];
    require(block.timestamp > _stake.lastStaked + lockupPeriod, 'LU');
    uint256 _amtToBurn = (_amount * _stake.stakedToOutputFactor) /
      _stake.stakedToOutputDenomenator;
    _stake.amtStaked -= _amount;
    _burn(_msgSender(), _amtToBurn);
    IERC20(_asset).safeTransfer(_msgSender(), _amount);
    emit Unstake(_msgSender(), _asset, _amount);
  }

  function addOrUpdateAsset(
    address _asset,
    IStakingConversionFactor _convFactor,
    bool _enabled
  ) external onlyOwner {
    assets[_asset] = Asset({ enabled: _enabled, convFactor: _convFactor });
  }

  function enableAsset(address _asset) external onlyOwner {
    require(!assets[_asset].enabled, 'T');
    assets[_asset].enabled = true;
  }

  function disableAsset(address _asset) external onlyOwner {
    require(assets[_asset].enabled, 'T');
    assets[_asset].enabled = false;
  }

  function setLockupPeriod(uint256 _newLockup) external onlyOwner {
    require(_newLockup <= 112 days, 'M'); // 16 weeks
    lockupPeriod = _newLockup;
  }

  function _afterTokenTransfer(
    address _from,
    address _to,
    uint256 _amount
  ) internal virtual override {
    require(_from == address(0) || _to == address(0), 'NT');
    if (_from != address(0) && _from != address(0xdead)) {
      TokenRewards(REWARDS).setShares(_from, _amount, true);
    }
    if (_to != address(0) && _to != address(0xdead)) {
      TokenRewards(REWARDS).setShares(_to, _amount, false);
    }
  }
}

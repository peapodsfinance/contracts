// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './interfaces/IDexAdapter.sol';
import './interfaces/IRewardsWhitelister.sol';
import './interfaces/IProtocolFeeRouter.sol';
import './interfaces/IStakingPoolToken.sol';
import './TokenRewards.sol';

contract StakingPoolToken is IStakingPoolToken, ERC20, Ownable {
  using SafeERC20 for IERC20;

  address public immutable override INDEX_FUND;
  address public immutable override POOL_REWARDS;

  address public override stakeUserRestriction;
  address public override stakingToken;

  IDexAdapter immutable DEX_ADAPTER;
  IV3TwapUtilities immutable V3_TWAP_UTILS;

  modifier onlyRestricted() {
    require(_msgSender() == stakeUserRestriction, 'R');
    _;
  }

  constructor(
    string memory _name,
    string memory _symbol,
    address _pairedLpToken,
    address _rewardsToken,
    address _stakeUserRestriction,
    IProtocolFeeRouter _feeRouter,
    IRewardsWhitelister _rewardsWhitelist,
    IDexAdapter _dexAdapter,
    IV3TwapUtilities _v3TwapUtilities
  ) ERC20(_name, _symbol) {
    stakeUserRestriction = _stakeUserRestriction;
    INDEX_FUND = _msgSender();
    DEX_ADAPTER = _dexAdapter;
    V3_TWAP_UTILS = _v3TwapUtilities;
    POOL_REWARDS = address(
      new TokenRewards(
        _feeRouter,
        _rewardsWhitelist,
        _dexAdapter,
        _v3TwapUtilities,
        INDEX_FUND,
        _pairedLpToken,
        address(this),
        _rewardsToken
      )
    );
  }

  /// @dev backwards compatibility
  function indexFund() external view override returns (address) {
    return INDEX_FUND;
  }

  /// @dev backwards compatibility
  function poolRewards() external view override returns (address) {
    return POOL_REWARDS;
  }

  function stake(address _user, uint256 _amount) external override {
    require(stakingToken != address(0), 'I');
    if (stakeUserRestriction != address(0)) {
      require(_user == stakeUserRestriction, 'U');
    }
    _mint(_user, _amount);
    IERC20(stakingToken).safeTransferFrom(_msgSender(), address(this), _amount);
    emit Stake(_msgSender(), _user, _amount);
  }

  function unstake(uint256 _amount) external override {
    _burn(_msgSender(), _amount);
    IERC20(stakingToken).safeTransfer(_msgSender(), _amount);
    emit Unstake(_msgSender(), _amount);
  }

  function setStakingToken(address _stakingToken) external onlyOwner {
    require(stakingToken == address(0), 'S');
    stakingToken = _stakingToken;
  }

  function removeStakeUserRestriction() external onlyRestricted {
    stakeUserRestriction = address(0);
  }

  function setStakeUserRestriction(address _user) external onlyRestricted {
    stakeUserRestriction = _user;
  }

  function _afterTokenTransfer(
    address _from,
    address _to,
    uint256 _amount
  ) internal override {
    if (_from != address(0)) {
      TokenRewards(POOL_REWARDS).setShares(_from, _amount, true);
    }
    if (_to != address(0) && _to != address(0xdead)) {
      TokenRewards(POOL_REWARDS).setShares(_to, _amount, false);
    }
  }
}

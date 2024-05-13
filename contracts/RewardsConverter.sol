// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';
import './interfaces/IDecentralizedIndex.sol';
import './interfaces/IDexAdapter.sol';
import './interfaces/IIndexUtils.sol';
import './interfaces/IV3TwapUtilities.sol';
import './Zapper.sol';

contract RewardsConverter is Zapper {
  using SafeERC20 for IERC20;

  uint24 constant REWARDS_POOL_FEE = 10000;
  uint256 constant DEFAULT_SLIPPAGE = 50;

  IDexAdapter immutable DEX_HANDLER;
  IIndexUtils immutable INDEX_UTILS;

  constructor(
    IDexAdapter _dexHandler,
    IIndexUtils _utils,
    IV3TwapUtilities _v3TwapUtilities
  ) Zapper(_dexHandler.V2_ROUTER(), _v3TwapUtilities) {
    DEX_HANDLER = _dexHandler;
    INDEX_UTILS = _utils;
  }

  function _tokenToPairedLpToken(
    IDecentralizedIndex _pod,
    address _token,
    uint256 _amountIn,
    uint256 _amountOutMin,
    uint256 _slippageOverride
  ) internal returns (uint256 _amountOut) {
    address _pairedLpToken = _pod.PAIRED_LP_TOKEN();
    address _rewardsToken = _pod.lpRewardsToken();
    if (_token != address(0) && _token != _rewardsToken) {
      return _zap(_token, _pairedLpToken, _amountIn, _amountOutMin);
    }
    (address _token0, address _token1) = _pairedLpToken < _rewardsToken
      ? (_pairedLpToken, _rewardsToken)
      : (_rewardsToken, _pairedLpToken);
    address _pool = DEX_HANDLER.getV3Pool(_token0, _token1, REWARDS_POOL_FEE);
    uint160 _rewardsSqrtPriceX96 = V3_TWAP_UTILS
      .sqrtPriceX96FromPoolAndInterval(_pool);
    uint256 _rewardsPriceX96 = V3_TWAP_UTILS.priceX96FromSqrtPriceX96(
      _rewardsSqrtPriceX96
    );
    if (_amountOutMin == 0) {
      uint256 _amountOutNoSlip = _token0 == _rewardsToken
        ? (_rewardsPriceX96 * _amountIn) / FixedPoint96.Q96
        : (_amountIn * FixedPoint96.Q96) / _rewardsPriceX96;
      uint256 _slippage = _slippageOverride > 0
        ? _slippageOverride
        : DEFAULT_SLIPPAGE;
      _amountOutMin = (_amountOutNoSlip * (1000 - _slippage)) / 1000;
    }
    IERC20(_rewardsToken).safeIncreaseAllowance(
      address(DEX_HANDLER),
      _amountIn
    );
    return
      DEX_HANDLER.swapV3Single(
        _rewardsToken,
        _pairedLpToken,
        REWARDS_POOL_FEE,
        _amountIn,
        _amountOutMin,
        address(this)
      );
  }

  function _pairedLpTokenToPodLp(
    IDecentralizedIndex _pod,
    uint256 _amountIn,
    uint256 _amountOutMin,
    uint256 _deadline
  ) internal returns (uint256 _amountOut) {
    address _pairedLpToken = _pod.PAIRED_LP_TOKEN();
    uint256 _half = _amountIn / 2;
    IERC20(_pairedLpToken).safeIncreaseAllowance(address(DEX_HANDLER), _half);
    DEX_HANDLER.swapV2Single(
      _pairedLpToken,
      address(_pod),
      _half,
      _amountOutMin,
      address(this)
    );
    return
      INDEX_UTILS.addLPAndStake(
        _pod,
        _pod.balanceOf(address(this)),
        _pairedLpToken,
        _half,
        _half,
        DEFAULT_SLIPPAGE,
        _deadline
      );
  }
}

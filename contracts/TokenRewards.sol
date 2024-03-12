// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/Context.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol';
import './interfaces/IDecentralizedIndex.sol';
import './interfaces/IPEAS.sol';
import './interfaces/IRewardsWhitelister.sol';
import './interfaces/IProtocolFees.sol';
import './interfaces/IProtocolFeeRouter.sol';
import './interfaces/ISwapRouterAlgebra.sol';
import './interfaces/ITokenRewards.sol';
import './interfaces/IV3TwapUtilities.sol';
import './libraries/BokkyPooBahsDateTimeLibrary.sol';

contract TokenRewards is ITokenRewards, Context {
  using SafeERC20 for IERC20;

  uint256 constant PRECISION = 10 ** 36;
  uint24 constant REWARDS_POOL_FEE = 10000; // 1%
  address immutable V3_ROUTER;
  address immutable INDEX_FUND;
  address immutable PAIRED_LP_TOKEN;
  IProtocolFeeRouter immutable PROTOCOL_FEE_ROUTER;
  IRewardsWhitelister immutable REWARDS_WHITELISTER;
  IV3TwapUtilities immutable V3_TWAP_UTILS;

  struct Reward {
    uint256 excluded;
    uint256 realized;
  }

  address public immutable override trackingToken;
  address public immutable override rewardsToken; // main rewards token
  uint256 public override totalShares;
  uint256 public override totalStakers;
  mapping(address => uint256) public shares;
  // reward token => user => Reward
  mapping(address => mapping(address => Reward)) public rewards;

  uint256 _rewardsSwapSlippage = 20; // 2%
  // reward token => amount
  mapping(address => uint256) _rewardsPerShare;
  // reward token => amount
  mapping(address => uint256) public rewardsDistributed;
  // reward token => amount
  mapping(address => uint256) public rewardsDeposited;
  // reward token => month => amount
  mapping(address => mapping(uint256 => uint256)) public rewardsDepMonthly;
  // all deposited rewards tokens
  address[] _allRewardsTokens;
  mapping(address => bool) _depositedRewardsToken;

  constructor(
    IProtocolFeeRouter _feeRouter,
    IRewardsWhitelister _rewardsWhitelist,
    IV3TwapUtilities _v3TwapUtilities,
    address _v3Router,
    address _indexFund,
    address _pairedLpToken,
    address _trackingToken,
    address _rewardsToken
  ) {
    PROTOCOL_FEE_ROUTER = _feeRouter;
    REWARDS_WHITELISTER = _rewardsWhitelist;
    V3_TWAP_UTILS = _v3TwapUtilities;
    V3_ROUTER = _v3Router;
    INDEX_FUND = _indexFund;
    PAIRED_LP_TOKEN = _pairedLpToken;
    trackingToken = _trackingToken;
    rewardsToken = _rewardsToken;
  }

  function setShares(
    address _wallet,
    uint256 _amount,
    bool _sharesRemoving
  ) external override {
    require(_msgSender() == trackingToken, 'UNAUTHORIZED');
    _setShares(_wallet, _amount, _sharesRemoving);
  }

  function _setShares(
    address _wallet,
    uint256 _amount,
    bool _sharesRemoving
  ) internal {
    _processFeesIfApplicable();
    if (_sharesRemoving) {
      _removeShares(_wallet, _amount);
      emit RemoveShares(_wallet, _amount);
    } else {
      _addShares(_wallet, _amount);
      emit AddShares(_wallet, _amount);
    }
  }

  function _addShares(address _wallet, uint256 _amount) internal {
    if (shares[_wallet] > 0) {
      _distributeReward(_wallet);
    }
    uint256 sharesBefore = shares[_wallet];
    totalShares += _amount;
    shares[_wallet] += _amount;
    if (sharesBefore == 0 && shares[_wallet] > 0) {
      totalStakers++;
    }
  }

  function _removeShares(address _wallet, uint256 _amount) internal {
    require(shares[_wallet] > 0 && _amount <= shares[_wallet], 'REMOVE');
    _distributeReward(_wallet);
    totalShares -= _amount;
    shares[_wallet] -= _amount;
    if (shares[_wallet] == 0) {
      totalStakers--;
    }
  }

  function _processFeesIfApplicable() internal {
    IDecentralizedIndex(INDEX_FUND).processPreSwapFeesAndSwap();
  }

  function depositFromPairedLpToken(
    uint256 _amountTknDepositing,
    uint256 _slippageOverride
  ) public override {
    require(PAIRED_LP_TOKEN != rewardsToken, 'LPREWSAME');
    require(_slippageOverride <= 200, 'MAXSLIP'); // 20%
    if (_amountTknDepositing > 0) {
      IERC20(PAIRED_LP_TOKEN).safeTransferFrom(
        _msgSender(),
        address(this),
        _amountTknDepositing
      );
    }
    uint256 _amountTkn = IERC20(PAIRED_LP_TOKEN).balanceOf(address(this));
    require(_amountTkn > 0, 'NEEDTKN');
    uint256 _adminAmt;
    (uint256 _yieldAdminFee, ) = _getYieldFees();
    if (_yieldAdminFee > 0) {
      _adminAmt =
        (_amountTkn * _yieldAdminFee) /
        PROTOCOL_FEE_ROUTER.protocolFees().DEN();
      _amountTkn -= _adminAmt;
    }
    (address _token0, address _token1) = PAIRED_LP_TOKEN < rewardsToken
      ? (PAIRED_LP_TOKEN, rewardsToken)
      : (rewardsToken, PAIRED_LP_TOKEN);
    address _pool;
    if (block.chainid == 42161) {
      _pool = V3_TWAP_UTILS.getV3Pool(
        IPeripheryImmutableState(V3_ROUTER).factory(),
        _token0,
        _token1
      );
    } else {
      _pool = V3_TWAP_UTILS.getV3Pool(
        IPeripheryImmutableState(V3_ROUTER).factory(),
        _token0,
        _token1,
        REWARDS_POOL_FEE
      );
    }
    uint160 _rewardsSqrtPriceX96 = V3_TWAP_UTILS
      .sqrtPriceX96FromPoolAndInterval(_pool);
    uint256 _rewardsPriceX96 = V3_TWAP_UTILS.priceX96FromSqrtPriceX96(
      _rewardsSqrtPriceX96
    );
    uint256 _amountOut = _token0 == PAIRED_LP_TOKEN
      ? (_rewardsPriceX96 * _amountTkn) / FixedPoint96.Q96
      : (_amountTkn * FixedPoint96.Q96) / _rewardsPriceX96;

    IERC20(PAIRED_LP_TOKEN).safeIncreaseAllowance(V3_ROUTER, _amountTkn);
    uint256 _slippage = _slippageOverride > 0
      ? _slippageOverride
      : _rewardsSwapSlippage;
    _swapForRewards(
      _amountTkn,
      _amountOut,
      _slippage,
      _slippageOverride > 0,
      _adminAmt
    );
  }

  function depositRewards(address _token, uint256 _amount) external override {
    require(_isValidRewardsToken(_token), 'VALID');
    if (!_depositedRewardsToken[_token]) {
      _depositedRewardsToken[_token] = true;
      _allRewardsTokens.push(_token);
    }
    require(_amount > 0, 'DEPAM');
    uint256 _rewardsBalBefore = IERC20(_token).balanceOf(address(this));
    IERC20(_token).safeTransferFrom(_msgSender(), address(this), _amount);
    _depositRewards(
      _token,
      IERC20(_token).balanceOf(address(this)) - _rewardsBalBefore
    );
  }

  function _depositRewards(address _token, uint256 _amountTotal) internal {
    if (_amountTotal == 0) {
      return;
    }
    if (totalShares == 0) {
      _burnRewards(_amountTotal);
      return;
    }

    uint256 _depositAmount = _amountTotal;
    (, uint256 _yieldBurnFee) = _getYieldFees();
    if (_yieldBurnFee > 0) {
      uint256 _burnAmount = (_amountTotal * _yieldBurnFee) /
        PROTOCOL_FEE_ROUTER.protocolFees().DEN();
      if (_burnAmount > 0) {
        _burnRewards(_burnAmount);
        _depositAmount -= _burnAmount;
      }
    }
    rewardsDeposited[_token] += _depositAmount;
    rewardsDepMonthly[_token][
      beginningOfMonth(block.timestamp)
    ] += _depositAmount;
    _rewardsPerShare[_token] += (PRECISION * _depositAmount) / totalShares;
    emit DepositRewards(_msgSender(), _token, _depositAmount);
  }

  function _distributeReward(address _wallet) internal {
    if (shares[_wallet] == 0) {
      return;
    }
    for (uint256 _i; _i < _allRewardsTokens.length; _i++) {
      address _token = _allRewardsTokens[_i];
      uint256 _amount = getUnpaid(_token, _wallet);
      rewards[_token][_wallet].realized += _amount;
      rewards[_token][_wallet].excluded = _cumulativeRewards(
        _token,
        shares[_wallet]
      );
      if (_amount > 0) {
        rewardsDistributed[_token] += _amount;
        IERC20(_token).safeTransfer(_wallet, _amount);
        emit DistributeReward(_wallet, _token, _amount);
      }
    }
  }

  function _burnRewards(uint256 _burnAmount) internal {
    try IPEAS(rewardsToken).burn(_burnAmount) {} catch {
      IERC20(rewardsToken).safeTransfer(address(0xdead), _burnAmount);
    }
  }

  function _isValidRewardsToken(address _token) internal view returns (bool) {
    return _token == rewardsToken || REWARDS_WHITELISTER.whitelist(_token);
  }

  function _getYieldFees()
    internal
    view
    returns (uint256 _admin, uint256 _burn)
  {
    IProtocolFees _fees = PROTOCOL_FEE_ROUTER.protocolFees();
    if (address(_fees) != address(0)) {
      _admin = _fees.yieldAdmin();
      _burn = _fees.yieldBurn();
    }
  }

  function _swapForRewards(
    uint256 _amountIn,
    uint256 _amountOut,
    uint256 _slippage,
    bool _isSlipOverride,
    uint256 _adminAmt
  ) internal {
    uint256 _rewardsBalBefore = IERC20(rewardsToken).balanceOf(address(this));
    if (block.chainid == 42161) {
      try
        ISwapRouterAlgebra(V3_ROUTER).exactInputSingle(
          ISwapRouterAlgebra.ExactInputSingleParams({
            tokenIn: PAIRED_LP_TOKEN,
            tokenOut: rewardsToken,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: (_amountOut * (1000 - _slippage)) / 1000,
            limitSqrtPrice: 0
          })
        )
      {
        if (_adminAmt > 0) {
          IERC20(PAIRED_LP_TOKEN).safeTransfer(
            Ownable(address(V3_TWAP_UTILS)).owner(),
            _adminAmt
          );
        }
        _rewardsSwapSlippage = 20;
        _depositRewards(
          rewardsToken,
          IERC20(rewardsToken).balanceOf(address(this)) - _rewardsBalBefore
        );
      } catch {
        if (!_isSlipOverride && _rewardsSwapSlippage < 200) {
          _rewardsSwapSlippage += 10;
        }
        IERC20(PAIRED_LP_TOKEN).safeDecreaseAllowance(V3_ROUTER, _amountIn);
      }
    } else {
      try
        ISwapRouter(V3_ROUTER).exactInputSingle(
          ISwapRouter.ExactInputSingleParams({
            tokenIn: PAIRED_LP_TOKEN,
            tokenOut: rewardsToken,
            fee: REWARDS_POOL_FEE,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: _amountIn,
            amountOutMinimum: (_amountOut * (1000 - _slippage)) / 1000,
            sqrtPriceLimitX96: 0
          })
        )
      {
        if (_adminAmt > 0) {
          IERC20(PAIRED_LP_TOKEN).safeTransfer(
            Ownable(address(V3_TWAP_UTILS)).owner(),
            _adminAmt
          );
        }
        _rewardsSwapSlippage = 10;
        _depositRewards(
          rewardsToken,
          IERC20(rewardsToken).balanceOf(address(this)) - _rewardsBalBefore
        );
      } catch {
        if (_rewardsSwapSlippage < 200) {
          _rewardsSwapSlippage += 10;
        }
        IERC20(PAIRED_LP_TOKEN).safeDecreaseAllowance(V3_ROUTER, _amountIn);
      }
    }
  }

  function beginningOfMonth(uint256 _timestamp) public pure returns (uint256) {
    (, , uint256 _dayOfMonth) = BokkyPooBahsDateTimeLibrary.timestampToDate(
      _timestamp
    );
    return _timestamp - ((_dayOfMonth - 1) * 1 days) - (_timestamp % 1 days);
  }

  function claimReward(address _wallet) external override {
    _distributeReward(_wallet);
    emit ClaimReward(_wallet);
  }

  function getUnpaid(address _wallet) external view returns (uint256) {
    if (shares[_wallet] == 0) {
      return 0;
    }
    uint256 earnedRewards = _cumulativeRewards(rewardsToken, shares[_wallet]);
    uint256 rewardsExcluded = rewards[rewardsToken][_wallet].excluded;
    if (earnedRewards <= rewardsExcluded) {
      return 0;
    }
    return earnedRewards - rewardsExcluded;
  }

  function getUnpaid(
    address _token,
    address _wallet
  ) public view returns (uint256) {
    if (shares[_wallet] == 0) {
      return 0;
    }
    uint256 earnedRewards = _cumulativeRewards(_token, shares[_wallet]);
    uint256 rewardsExcluded = rewards[_token][_wallet].excluded;
    if (earnedRewards <= rewardsExcluded) {
      return 0;
    }
    return earnedRewards - rewardsExcluded;
  }

  function _cumulativeRewards(
    address _token,
    uint256 _share
  ) internal view returns (uint256) {
    return (_share * _rewardsPerShare[_token]) / PRECISION;
  }
}

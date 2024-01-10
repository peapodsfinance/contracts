// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';
import '@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import './interfaces/IDecentralizedIndex.sol';
import './interfaces/IERC20Metadata.sol';
import './interfaces/IStakingPoolToken.sol';
import './interfaces/ITokenRewards.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV3Pool.sol';
import './interfaces/IUniswapV2Router02.sol';
import './interfaces/IV3TwapUtilities.sol';
import './interfaces/IWETH.sol';

contract IndexUtils is Context, Ownable {
  using SafeERC20 for IERC20;

  address constant V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  address immutable V2_ROUTER;
  address immutable WETH;
  IV3TwapUtilities immutable V3_TWAP_UTILS;

  constructor(address _v2Router, IV3TwapUtilities _v3TwapUtilities) {
    V2_ROUTER = _v2Router;
    V3_TWAP_UTILS = _v3TwapUtilities;
    WETH = IUniswapV2Router02(_v2Router).WETH();
  }

  function bond(
    IDecentralizedIndex _indexFund,
    address _token,
    uint256 _amount
  ) external {
    if (_indexFund.indexType() == IDecentralizedIndex.IndexType.WEIGHTED) {
      IDecentralizedIndex.IndexAssetInfo[] memory _assets = _indexFund
        .getAllAssets();
      uint256[] memory _balsBefore = new uint256[](_assets.length);
      uint256 _tokenIdx;
      for (uint256 _i; _i < _assets.length; _i++) {
        if (_assets[_i].token == _token) {
          _tokenIdx = _i;
        }
      }

      uint256 _tokenCurSupply = IERC20(_token).balanceOf(address(_indexFund));
      uint256 _tokenAmtSupplyRatioX96 = _tokenCurSupply == 0
        ? FixedPoint96.Q96
        : (_amount * FixedPoint96.Q96) / _tokenCurSupply;
      for (uint256 _i; _i < _assets.length; _i++) {
        uint256 _amountNeeded = _tokenAmtSupplyRatioX96 == FixedPoint96.Q96
          ? _indexFund.getInitialAmount(_token, _amount, _assets[_i].token)
          : (IERC20(_assets[_i].token).balanceOf(address(_indexFund)) *
            _tokenAmtSupplyRatioX96) / FixedPoint96.Q96;
        _balsBefore[_i] = IERC20(_assets[_i].token).balanceOf(address(this));
        IERC20(_assets[_i].token).safeTransferFrom(
          _msgSender(),
          address(this),
          _amountNeeded
        );
        IERC20(_assets[_i].token).safeIncreaseAllowance(
          address(_indexFund),
          _amountNeeded
        );
      }
      uint256 _idxBalBefore = IERC20(_indexFund).balanceOf(address(this));
      _indexFund.bond(_token, _amount);
      IERC20(_indexFund).safeTransfer(
        _msgSender(),
        IERC20(_indexFund).balanceOf(address(this)) - _idxBalBefore
      );
    } else {
      require(
        _indexFund.indexType() == IDecentralizedIndex.IndexType.UNWEIGHTED,
        'UW'
      );
      IERC20(_token).safeTransferFrom(_msgSender(), address(this), _amount);
      IERC20(_token).safeIncreaseAllowance(address(_indexFund), _amount);
      uint256 _idxBalBefore = IERC20(_indexFund).balanceOf(address(this));
      _indexFund.bond(_token, _amount);
      IERC20(_indexFund).safeTransfer(
        _msgSender(),
        IERC20(_indexFund).balanceOf(address(this)) - _idxBalBefore
      );
    }
  }

  function bondWeightedFromNative(
    IDecentralizedIndex _indexFund,
    uint256 _assetIdx,
    uint256 _amountTokensForAssetIdx,
    uint256 _slippage, // 1 == 0.1%, 10 == 1%, 1000 == 100%
    bool _stakeAsWell
  ) external payable {
    require(msg.value > 0, 'NATIVE');
    uint256 _ethBalBefore = address(this).balance - msg.value;
    IDecentralizedIndex.IndexAssetInfo[] memory _assets = _indexFund
      .getAllAssets();
    uint256 _nativeForAssets = _stakeAsWell ? msg.value / 2 : msg.value;
    (
      uint256[] memory _balancesBefore,
      uint256[] memory _amountsReceived
    ) = _swapNativeForTokensWeightedV2(
        _indexFund,
        _nativeForAssets,
        _assets,
        _assetIdx,
        _amountTokensForAssetIdx
      );

    // allowance for _assetIdx is increased in _bondToRecipient below,
    // we just need to increase allowance for any other index tokens here first
    for (uint256 _i; _i < _assets.length; _i++) {
      if (_i == _assetIdx) {
        continue;
      }
      IERC20(_assets[_i].token).safeIncreaseAllowance(
        address(_indexFund),
        _amountsReceived[_i]
      );
    }
    uint256 _idxTokensGained = _bondToRecipient(
      _indexFund,
      _assets[_assetIdx].token,
      _amountsReceived[_assetIdx],
      _stakeAsWell ? address(this) : _msgSender()
    );

    if (_stakeAsWell) {
      _zapIndexTokensAndNative(
        _msgSender(),
        _indexFund,
        _idxTokensGained,
        msg.value / 2,
        _slippage
      );
    }

    // refund any excess tokens to user we didn't use to bond
    for (uint256 _i; _i < _assets.length; _i++) {
      uint256 _balNow = IERC20(_assets[_i].token).balanceOf(address(this));
      if (_balNow > _balancesBefore[_i]) {
        IERC20(_assets[_i].token).safeTransfer(
          _msgSender(),
          _balNow - _balancesBefore[_i]
        );
      }
    }

    // refund excess ETH
    if (address(this).balance > _ethBalBefore) {
      (bool _sent, ) = payable(_msgSender()).call{
        value: address(this).balance - _ethBalBefore
      }('');
      require(_sent, 'ETHREFUND');
    }
  }

  function bondUnweightedFromNative(
    IDecentralizedIndex _indexFund,
    uint256 _poolIdx,
    uint256 _slippage, // 1 == 0.1%, 10 == 1%, 1000 == 100%
    bool _stakeAsWell
  ) external payable {
    require(msg.value > 0, 'NATIVE');
    uint256 _wethBalBefore = IERC20(WETH).balanceOf(address(this));
    IWETH(WETH).deposit{ value: _stakeAsWell ? msg.value / 2 : msg.value }();
    uint256 _wethToBond = IERC20(WETH).balanceOf(address(this)) -
      _wethBalBefore;
    uint256 _idxTokensGained = _bondUnweightedFromWrappedNative(
      _indexFund,
      _stakeAsWell ? address(this) : _msgSender(),
      _poolIdx,
      _wethToBond,
      _slippage
    );

    if (_stakeAsWell) {
      _zapIndexTokensAndNative(
        _msgSender(),
        _indexFund,
        _idxTokensGained,
        msg.value / 2,
        _slippage
      );
    }
  }

  function zapIndexTokensAndNative(
    IDecentralizedIndex _indexFund,
    uint256 _amount,
    uint256 _slippage
  ) external payable {
    require(msg.value > 0, 'NATIVE');
    IERC20(address(_indexFund)).safeTransferFrom(
      _msgSender(),
      address(this),
      _amount
    );
    _zapIndexTokensAndNative(
      _msgSender(),
      _indexFund,
      _amount,
      msg.value,
      _slippage
    );
  }

  function addLPAndStake(
    IDecentralizedIndex _indexFund,
    uint256 _amountIdxTokens,
    uint256 _amountPairedLpToken,
    uint256 _slippage
  ) external {
    address _stakingPool = _indexFund.lpStakingPool();
    address _pairedLpToken = _indexFund.PAIRED_LP_TOKEN();
    address _v2Pool = IUniswapV2Factory(IUniswapV2Router02(V2_ROUTER).factory())
      .getPair(address(_indexFund), _pairedLpToken);
    uint256 _idxTokensBefore = IERC20(address(_indexFund)).balanceOf(
      address(this)
    );
    uint256 _pairedLpTokenBefore = IERC20(_pairedLpToken).balanceOf(
      address(this)
    );
    uint256 _v2PoolBefore = IERC20(_v2Pool).balanceOf(address(this));
    IERC20(address(_indexFund)).safeTransferFrom(
      _msgSender(),
      address(this),
      _amountIdxTokens
    );
    IERC20(_pairedLpToken).safeTransferFrom(
      _msgSender(),
      address(this),
      _amountPairedLpToken
    );

    IERC20(_pairedLpToken).safeIncreaseAllowance(
      address(_indexFund),
      IERC20(_pairedLpToken).balanceOf(address(this)) - _pairedLpTokenBefore
    );
    _indexFund.addLiquidityV2(
      IERC20(address(_indexFund)).balanceOf(address(this)) - _idxTokensBefore,
      IERC20(_pairedLpToken).balanceOf(address(this)) - _pairedLpTokenBefore,
      _slippage
    );

    IERC20(_v2Pool).safeIncreaseAllowance(
      _stakingPool,
      IERC20(_v2Pool).balanceOf(address(this)) - _v2PoolBefore
    );
    IStakingPoolToken(_stakingPool).stake(
      _msgSender(),
      IERC20(_v2Pool).balanceOf(address(this)) - _v2PoolBefore
    );

    // refunds if needed for index tokens and pairedLpToken
    if (
      IERC20(address(_indexFund)).balanceOf(address(this)) > _idxTokensBefore
    ) {
      IERC20(address(_indexFund)).safeTransfer(
        _msgSender(),
        IERC20(address(_indexFund)).balanceOf(address(this)) - _idxTokensBefore
      );
    }
    if (
      IERC20(_pairedLpToken).balanceOf(address(this)) > _pairedLpTokenBefore
    ) {
      IERC20(_pairedLpToken).safeTransfer(
        _msgSender(),
        IERC20(_pairedLpToken).balanceOf(address(this)) - _pairedLpTokenBefore
      );
    }
  }

  function unstakeAndRemoveLP(
    IDecentralizedIndex _indexFund,
    uint256 _amountStakedTokens,
    uint256 _minLPTokens,
    uint256 _minPairedLpToken
  ) external {
    address _stakingPool = _indexFund.lpStakingPool();
    address _pairedLpToken = _indexFund.PAIRED_LP_TOKEN();
    uint256 _stakingBalBefore = IERC20(_stakingPool).balanceOf(address(this));
    uint256 _pairedLpTokenBefore = IERC20(_pairedLpToken).balanceOf(
      address(this)
    );
    IERC20(_stakingPool).safeTransferFrom(
      _msgSender(),
      address(this),
      _amountStakedTokens
    );
    uint256 _indexBalBefore = _unstakeAndRemoveLP(
      _indexFund,
      _stakingPool,
      IERC20(_stakingPool).balanceOf(address(this)) - _stakingBalBefore,
      _minLPTokens,
      _minPairedLpToken
    );
    if (
      IERC20(address(_indexFund)).balanceOf(address(this)) > _indexBalBefore
    ) {
      IERC20(address(_indexFund)).safeTransfer(
        _msgSender(),
        IERC20(address(_indexFund)).balanceOf(address(this)) - _indexBalBefore
      );
    }
    if (
      IERC20(_pairedLpToken).balanceOf(address(this)) > _pairedLpTokenBefore
    ) {
      IERC20(_pairedLpToken).safeTransfer(
        _msgSender(),
        IERC20(_pairedLpToken).balanceOf(address(this)) - _pairedLpTokenBefore
      );
    }
  }

  function claimRewardsMulti(address[] memory _rewards) external {
    for (uint256 _i; _i < _rewards.length; _i++) {
      ITokenRewards(_rewards[_i]).claimReward(_msgSender());
    }
  }

  function _swapNativeForTokensWeightedV2(
    IDecentralizedIndex _indexFund,
    uint256 _amountNative,
    IDecentralizedIndex.IndexAssetInfo[] memory _assets,
    uint256 _poolIdx,
    uint256 _amountForPoolIdx
  ) internal returns (uint256[] memory, uint256[] memory) {
    uint256[] memory _amountBefore = new uint256[](_assets.length);
    uint256[] memory _amountReceived = new uint256[](_assets.length);
    uint256 _tokenCurSupply = IERC20(_assets[_poolIdx].token).balanceOf(
      address(_indexFund)
    );
    uint256 _tokenAmtSupplyRatioX96 = _tokenCurSupply == 0
      ? FixedPoint96.Q96
      : (_amountForPoolIdx * FixedPoint96.Q96) / _tokenCurSupply;
    uint256 _nativeLeft = _amountNative;
    for (uint256 _i; _i < _assets.length; _i++) {
      (_nativeLeft, _amountBefore[_i], _amountReceived[_i]) = _swapForIdxToken(
        _indexFund,
        _assets[_poolIdx].token,
        _amountForPoolIdx,
        _assets[_i].token,
        _tokenAmtSupplyRatioX96,
        _nativeLeft
      );
    }
    return (_amountBefore, _amountReceived);
  }

  function _swapForIdxToken(
    IDecentralizedIndex _indexFund,
    address _initToken,
    uint256 _initTokenAmount,
    address _outToken,
    uint256 _tokenAmtSupplyRatioX96,
    uint256 _nativeLeft
  )
    internal
    returns (
      uint256 _newNativeLeft,
      uint256 _amountBefore,
      uint256 _amountReceived
    )
  {
    uint256 _nativeBefore = address(this).balance;
    _amountBefore = IERC20(_outToken).balanceOf(address(this));
    uint256 _amountOut = _tokenAmtSupplyRatioX96 == FixedPoint96.Q96
      ? _indexFund.getInitialAmount(_initToken, _initTokenAmount, _outToken)
      : (IERC20(_outToken).balanceOf(address(_indexFund)) *
        _tokenAmtSupplyRatioX96) / FixedPoint96.Q96;
    address[] memory _path = new address[](2);
    _path[0] = IUniswapV2Router02(V2_ROUTER).WETH();
    _path[1] = _outToken;
    IUniswapV2Router02(V2_ROUTER).swapETHForExactTokens{ value: _nativeLeft }(
      _amountOut,
      _path,
      address(this),
      block.timestamp
    );
    _newNativeLeft -= _nativeBefore - address(this).balance;
    _amountReceived =
      IERC20(_outToken).balanceOf(address(this)) -
      _amountBefore;
  }

  function _bondUnweightedFromWrappedNative(
    IDecentralizedIndex _indexFund,
    address _recipient,
    uint256 _poolIdx,
    uint256 _wethToBond,
    uint256 _slippage // 1 == 0.1%, 10 == 1%, 1000 == 100%
  ) internal returns (uint256) {
    IDecentralizedIndex.IndexAssetInfo[] memory _assets = _indexFund
      .getAllAssets();

    uint256 _bondingTokensGained;
    if (_assets[_poolIdx].token == WETH) {
      _bondingTokensGained = _wethToBond;
    } else {
      uint256 _poolPriceX96 = V3_TWAP_UTILS.priceX96FromSqrtPriceX96(
        V3_TWAP_UTILS.sqrtPriceX96FromPoolAndInterval(_assets[_poolIdx].c1)
      );
      address _token0 = WETH < address(_indexFund) ? WETH : address(_indexFund);
      uint256 _amountOut = _token0 == WETH
        ? (_poolPriceX96 * _wethToBond) / FixedPoint96.Q96
        : (_wethToBond * FixedPoint96.Q96) / _poolPriceX96;

      IERC20(WETH).safeIncreaseAllowance(V3_ROUTER, _wethToBond);
      _bondingTokensGained = ISwapRouter(V3_ROUTER).exactInputSingle(
        ISwapRouter.ExactInputSingleParams({
          tokenIn: WETH,
          tokenOut: _assets[_poolIdx].token,
          fee: IUniswapV3Pool(_assets[_poolIdx].c1).fee(),
          recipient: address(this),
          deadline: block.timestamp,
          amountIn: _wethToBond,
          amountOutMinimum: (_amountOut * (1000 - _slippage)) / 1000,
          sqrtPriceLimitX96: 0
        })
      );
    }
    return
      _bondToRecipient(
        _indexFund,
        _assets[_poolIdx].token,
        _bondingTokensGained,
        _recipient
      );
  }

  function _unstakeAndRemoveLP(
    IDecentralizedIndex _indexFund,
    address _stakingPool,
    uint256 _unstakeAmount,
    uint256 _minLPTokens,
    uint256 _minPairedLpTokens
  ) internal returns (uint256 _fundTokensBefore) {
    address _pairedLpToken = _indexFund.PAIRED_LP_TOKEN();
    address _v2Pool = IUniswapV2Factory(IUniswapV2Router02(V2_ROUTER).factory())
      .getPair(address(_indexFund), _pairedLpToken);
    uint256 _v2TokensBefore = IERC20(_v2Pool).balanceOf(address(this));
    IStakingPoolToken(_stakingPool).unstake(_unstakeAmount);

    _fundTokensBefore = _indexFund.balanceOf(address(this));
    IERC20(_v2Pool).safeIncreaseAllowance(
      address(_indexFund),
      IERC20(_v2Pool).balanceOf(address(this)) - _v2TokensBefore
    );
    _indexFund.removeLiquidityV2(
      IERC20(_v2Pool).balanceOf(address(this)) - _v2TokensBefore,
      _minLPTokens,
      _minPairedLpTokens
    );
  }

  function _swapToken0ForToken1V3(
    address _tokenIn,
    address _tokenOut,
    uint256 _amountIn,
    uint24 _poolFee,
    uint256 _slippage
  ) internal returns (uint256) {
    address _v3Pool = V3_TWAP_UTILS.getV3Pool(
      IPeripheryImmutableState(V3_ROUTER).factory(),
      _tokenIn,
      _tokenOut,
      _poolFee
    );
    address _token0 = _tokenIn < _tokenOut ? _tokenIn : _tokenOut;
    uint256 _poolPriceX96 = V3_TWAP_UTILS.priceX96FromSqrtPriceX96(
      V3_TWAP_UTILS.sqrtPriceX96FromPoolAndInterval(_v3Pool)
    );
    uint256 _amountOut = _tokenIn == _token0
      ? (_poolPriceX96 * _amountIn) / FixedPoint96.Q96
      : (_amountIn * FixedPoint96.Q96) / _poolPriceX96;
    IERC20(_tokenIn).safeIncreaseAllowance(V3_ROUTER, _amountIn);
    return
      ISwapRouter(V3_ROUTER).exactInputSingle(
        ISwapRouter.ExactInputSingleParams({
          tokenIn: _tokenIn,
          tokenOut: _tokenOut,
          fee: _poolFee,
          recipient: address(this),
          deadline: block.timestamp,
          amountIn: _amountIn,
          amountOutMinimum: (_amountOut * (1000 - _slippage)) / 1000,
          sqrtPriceLimitX96: 0
        })
      );
  }

  function _bondToRecipient(
    IDecentralizedIndex _indexFund,
    address _indexToken,
    uint256 _bondingTokens,
    address _recipient
  ) internal returns (uint256) {
    uint256 _idxTokensBefore = IERC20(address(_indexFund)).balanceOf(
      address(this)
    );
    IERC20(_indexToken).safeIncreaseAllowance(
      address(_indexFund),
      _bondingTokens
    );
    _indexFund.bond(_indexToken, _bondingTokens);
    uint256 _idxTokensGained = IERC20(address(_indexFund)).balanceOf(
      address(this)
    ) - _idxTokensBefore;
    if (_recipient != address(this)) {
      IERC20(address(_indexFund)).safeTransfer(_recipient, _idxTokensGained);
    }
    return _idxTokensGained;
  }

  function _zapIndexTokensAndNative(
    address _user,
    IDecentralizedIndex _indexFund,
    uint256 _amountTokens,
    uint256 _amountETH,
    uint256 _slippage
  ) internal {
    address _pairedLpToken = _indexFund.PAIRED_LP_TOKEN();
    uint256 _tokensBefore = IERC20(address(_indexFund)).balanceOf(
      address(this)
    );
    uint256 _wethBefore = IERC20(WETH).balanceOf(address(this));
    IWETH(WETH).deposit{ value: _amountETH }();

    uint256 _pairedLpTokenBefore = IERC20(_pairedLpToken).balanceOf(
      address(this)
    );
    address _stakingPool = _indexFund.lpStakingPool();

    _swapToken0ForToken1V3(
      WETH,
      _pairedLpToken,
      IERC20(WETH).balanceOf(address(this)) - _wethBefore,
      3000,
      _slippage
    );

    address _v2Pool = IUniswapV2Factory(IUniswapV2Router02(V2_ROUTER).factory())
      .getPair(address(_indexFund), _pairedLpToken);
    uint256 _lpTokensBefore = IERC20(_v2Pool).balanceOf(address(this));
    IERC20(_pairedLpToken).safeIncreaseAllowance(
      address(_indexFund),
      IERC20(_pairedLpToken).balanceOf(address(this)) - _pairedLpTokenBefore
    );
    _indexFund.addLiquidityV2(
      _amountTokens,
      IERC20(_pairedLpToken).balanceOf(address(this)) - _pairedLpTokenBefore,
      _slippage
    );
    IERC20(_v2Pool).safeIncreaseAllowance(
      _stakingPool,
      IERC20(_v2Pool).balanceOf(address(this)) - _lpTokensBefore
    );
    IStakingPoolToken(_stakingPool).stake(
      _user,
      IERC20(_v2Pool).balanceOf(address(this)) - _lpTokensBefore
    );

    // check & refund excess tokens from LPing as needed
    if (IERC20(address(_indexFund)).balanceOf(address(this)) > _tokensBefore) {
      IERC20(address(_indexFund)).safeTransfer(
        _user,
        IERC20(address(_indexFund)).balanceOf(address(this)) - _tokensBefore
      );
    }
    if (
      IERC20(_pairedLpToken).balanceOf(address(this)) > _pairedLpTokenBefore
    ) {
      IERC20(_pairedLpToken).safeTransfer(
        _user,
        IERC20(_pairedLpToken).balanceOf(address(this)) - _pairedLpTokenBefore
      );
    }
  }

  function rescueETH() external onlyOwner {
    (bool _sent, ) = payable(owner()).call{ value: address(this).balance }('');
    require(_sent);
  }

  function rescueERC20(IERC20 _token) external onlyOwner {
    _token.safeTransfer(owner(), _token.balanceOf(address(this)));
  }

  receive() external payable {}
}

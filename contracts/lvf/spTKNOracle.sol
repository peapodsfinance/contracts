// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';
import '../interfaces/IDecentralizedIndex.sol';
import '../interfaces/IStakingConversionFactor.sol';
import '../interfaces/IStakingPoolToken.sol';
import '../interfaces/IUniswapV3Pool.sol';
import '../interfaces/ICamelotPair.sol';
import '../interfaces/IMinimalOracle.sol';
import '../interfaces/IV3TwapUtilities.sol';

contract spTKNOracle is IMinimalOracle {
  address public immutable BASE_TOKEN;
  address public immutable SPTKN; // QUOTE_TOKEN
  address public immutable CL_POOL;
  IV3TwapUtilities public immutable TWAP_UTILS;

  constructor(
    address _baseToken,
    address _spTKN,
    address _pTKNBasePool,
    IV3TwapUtilities _utils
  ) {
    BASE_TOKEN = _baseToken;
    SPTKN = _spTKN;
    CL_POOL = _pTKNBasePool;
    TWAP_UTILS = _utils;
  }

  function getPrices()
    external
    view
    virtual
    override
    returns (bool _isBadData, uint256 _priceLow, uint256 _priceHigh)
  {
    uint256 _priceBaseSpTKNX96 = _basePerSpTKNX96();
    _isBadData = false;
    uint256 _priceMid = (_priceBaseSpTKNX96 * 10 ** 18) / FixedPoint96.Q96;
    _priceLow = (_priceMid * 99) / 100;
    _priceHigh = (_priceMid * 101) / 100;
  }

  function _basePerSpTKNX96() internal view returns (uint256) {
    address _lpTkn = _getLpTkn();
    uint160 _sqrtPriceX96 = TWAP_UTILS.sqrtPriceX96FromPoolAndInterval(CL_POOL);
    uint256 _priceX96 = TWAP_UTILS.priceX96FromSqrtPriceX96(_sqrtPriceX96);
    address _clToken0 = IUniswapV3Pool(CL_POOL).token0();
    address _clToken1 = IUniswapV3Pool(CL_POOL).token1();
    uint256 _priceAssetX96 = _clToken1 == BASE_TOKEN
      ? _priceX96
      : FixedPoint96.Q96 ** 2 / _priceX96;
    _priceAssetX96 =
      (10 ** IERC20Metadata(_clToken0).decimals() * _priceAssetX96) /
      10 ** IERC20Metadata(_clToken1).decimals();
    (uint112 _reserve0, uint112 _reserve1, , ) = ICamelotPair(_lpTkn)
      .getReserves();
    uint256 _k = uint256(_reserve0) * _reserve1;
    uint256 _kDec = 10 **
      IERC20Metadata(ICamelotPair(_lpTkn).token0()).decimals() *
      10 ** IERC20Metadata(ICamelotPair(_lpTkn).token1()).decimals();
    uint256 _avgBaseAssetInLpX96 = _sqrt((_priceAssetX96 * _k) / _kDec) *
      2 ** (96 / 2);
    return
      (_avgBaseAssetInLpX96 * 10 ** IERC20Metadata(_lpTkn).decimals()) /
      IERC20(_lpTkn).totalSupply();
  }

  function _getLpTkn() private view returns (address) {
    return IStakingPoolToken(SPTKN).stakingToken();
  }

  function _sqrt(uint256 x) private pure returns (uint256 y) {
    uint256 z = (x + 1) / 2;
    y = x;
    while (z < y) {
      y = z;
      z = (x / z + z) / 2;
    }
  }
}

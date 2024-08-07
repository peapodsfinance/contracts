// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';
import '../interfaces/IStakingConversionFactor.sol';
import '../interfaces/IStakingPoolToken.sol';
import '../interfaces/IUniswapV3Pool.sol';
import '../interfaces/ICamelotPair.sol';
import '../interfaces/IMinimalOracle.sol';
import '../interfaces/IV3TwapUtilities.sol';

contract spTKNOracle is IMinimalOracle, Ownable {
  address public immutable BASE_TOKEN;
  address public immutable SPTKN; // QUOTE_TOKEN
  address public immutable CL_POOL;
  IV3TwapUtilities public immutable TWAP_UTILS;

  // Chainlink Config
  address public immutable CHAINLINK_MULTIPLY_ADDRESS;
  address public immutable CHAINLINK_DIVIDE_ADDRESS;
  uint256 public immutable CHAINLINK_NORMALIZATION;
  uint256 public maxOracleDelay;
  bool public allowOnlyUniOracle;

  uint32 twapInterval = 10 minutes;

  constructor(
    address _baseToken,
    address _spTKN,
    address _pTKNBasePool,
    IV3TwapUtilities _utils,
    address _clMultAddress,
    address _clDivAddress,
    bool _allowOnlyUniOracle
  ) {
    BASE_TOKEN = _baseToken;
    SPTKN = _spTKN;
    CL_POOL = _pTKNBasePool;
    TWAP_UTILS = _utils;
    allowOnlyUniOracle = _allowOnlyUniOracle;

    CHAINLINK_MULTIPLY_ADDRESS = _clMultAddress;
    CHAINLINK_DIVIDE_ADDRESS = _clDivAddress;

    uint8 _clMultiplyDecimals = _clMultAddress != address(0)
      ? AggregatorV3Interface(_clMultAddress).decimals()
      : 0;
    uint8 _clDivideDecimals = _clDivAddress != address(0)
      ? AggregatorV3Interface(_clDivAddress).decimals()
      : 0;
    CHAINLINK_NORMALIZATION =
      10 **
        (18 +
          _clMultiplyDecimals -
          _clDivideDecimals +
          IERC20Metadata(_baseToken).decimals() -
          IERC20Metadata(_spTKN).decimals());
  }

  function getPrices()
    external
    view
    virtual
    override
    returns (bool _isBadData, uint256 _priceLow, uint256 _priceHigh)
  {
    uint256 _priceBaseSpTKN = _v3BasePerSpTKNX96();
    _isBadData = false;
    uint256 _priceMid18 = _priceBaseSpTKN *
      10 ** (18 - IERC20Metadata(BASE_TOKEN).decimals());
    uint256 _priceCl18;
    (_isBadData, _priceCl18) = _getChainlinkPrice();
    if (_isBadData) {
      if (allowOnlyUniOracle) {
        _isBadData = false;
        _priceLow = (_priceMid18 * 995) / 1000;
        _priceHigh = (_priceMid18 * 1005) / 1000;
      }
    } else {
      _priceLow = _priceMid18 > _priceCl18 ? _priceCl18 : _priceMid18;
      _priceHigh = _priceMid18 > _priceCl18 ? _priceMid18 : _priceCl18;
    }
  }

  function _v3BasePerSpTKNX96() internal view returns (uint256) {
    address _lpTkn = _getLpTkn();
    uint160 _sqrtPriceX96 = _getV3SqrtPriceX96();
    uint256 _priceX96 = TWAP_UTILS.priceX96FromSqrtPriceX96(_sqrtPriceX96);
    address _clT0 = IUniswapV3Pool(CL_POOL).token0();
    uint8 _clT0Decimals = IERC20Metadata(_clT0).decimals();
    address _clT1 = IUniswapV3Pool(CL_POOL).token1();
    uint8 _clT1Decimals = IERC20Metadata(_clT1).decimals();
    uint256 _priceAssetX96 = _clT1 == BASE_TOKEN
      ? _accountForCBR(_priceX96)
      : FixedPoint96.Q96 ** 2 / _accountForCBR(_priceX96);
    _priceAssetX96 = _clT1 == BASE_TOKEN
      ? (10 ** _clT0Decimals * _priceAssetX96) / 10 ** _clT1Decimals
      : (10 ** _clT1Decimals * _priceAssetX96) / 10 ** _clT0Decimals;
    (uint112 _reserve0, uint112 _reserve1, , ) = ICamelotPair(_lpTkn)
      .getReserves();
    uint256 _k = uint256(_reserve0) * _reserve1;
    uint256 _kDec = 10 **
      IERC20Metadata(ICamelotPair(_lpTkn).token0()).decimals() *
      10 ** IERC20Metadata(ICamelotPair(_lpTkn).token1()).decimals();
    uint256 _avgBaseAssetInLpX96 = _sqrt((_priceAssetX96 * _k) / _kDec) *
      2 ** (96 / 2);
    uint256 _lpPriceX96 = (2 *
      _avgBaseAssetInLpX96 *
      10 ** ((_clT0Decimals + _clT1Decimals) / 2)) /
      IERC20(_lpTkn).totalSupply();
    uint256 _baseTDecimals = _clT1 == BASE_TOKEN
      ? _clT1Decimals
      : _clT0Decimals;
    return (_lpPriceX96 * 10 ** _baseTDecimals) / FixedPoint96.Q96;
  }

  function _getChainlinkPrice()
    internal
    view
    returns (bool _isBadData, uint256 _price)
  {
    _price = uint256(1e36);

    // no CL oracle given
    if (
      CHAINLINK_MULTIPLY_ADDRESS == address(0) &&
      CHAINLINK_DIVIDE_ADDRESS == address(0)
    ) {
      _isBadData = true;
      return (_isBadData, _price);
    }

    if (CHAINLINK_MULTIPLY_ADDRESS != address(0)) {
      (, int256 _answer, , uint256 _updatedAt, ) = AggregatorV3Interface(
        CHAINLINK_MULTIPLY_ADDRESS
      ).latestRoundData();

      // If data is stale or negative, set bad data to true and return
      if (_answer <= 0 || (block.timestamp - _updatedAt > maxOracleDelay)) {
        _isBadData = true;
        return (_isBadData, _price);
      }
      _price = _price * uint256(_answer);
    }

    if (CHAINLINK_DIVIDE_ADDRESS != address(0)) {
      (, int256 _answer, , uint256 _updatedAt, ) = AggregatorV3Interface(
        CHAINLINK_DIVIDE_ADDRESS
      ).latestRoundData();

      // If data is stale or negative, set bad data to true and return
      if (_answer <= 0 || (block.timestamp - _updatedAt > maxOracleDelay)) {
        _isBadData = true;
        return (_isBadData, _price);
      }
      _price = _price / uint256(_answer);
    }

    // return price as ratio of Collateral/Asset including decimal differences
    // CHAINLINK_NORMALIZATION = 10**(18 + asset.decimals() - collateral.decimals() + multiplyOracle.decimals() - divideOracle.decimals())
    _price = _price / CHAINLINK_NORMALIZATION;
  }

  function _getV3SqrtPriceX96() internal view returns (uint160) {
    return
      TWAP_UTILS.sqrtPriceX96FromPoolAndPassedInterval(CL_POOL, twapInterval);
  }

  function _getLpTkn() private view returns (address) {
    return IStakingPoolToken(SPTKN).stakingToken();
  }

  function _accountForCBR(uint256 _underlying) internal view returns (uint256) {
    address _pod = IStakingPoolToken(SPTKN).INDEX_FUND();
    return
      (_underlying *
        IERC20(BASE_TOKEN).balanceOf(_pod) *
        10 ** IERC20Metadata(_pod).decimals()) /
      IERC20(_pod).totalSupply() /
      10 ** IERC20Metadata(BASE_TOKEN).decimals();
  }

  function _sqrt(uint256 x) private pure returns (uint256 y) {
    uint256 z = (x + 1) / 2;
    y = x;
    while (z < y) {
      y = z;
      z = (x / z + z) / 2;
    }
  }

  function setTwapInterval(uint32 _interval) external onlyOwner {
    twapInterval = _interval;
  }
}

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

  // Chainlink config
  address public immutable CHAINLINK_BASE_MULTIPLY_ADDRESS;
  address public immutable CHAINLINK_BASE_DIVIDE_ADDRESS;
  address public immutable CHAINLINK_PAIRED_MULTIPLY_ADDRESS;
  address public immutable CHAINLINK_PAIRED_DIVIDE_ADDRESS;
  uint256 public immutable CHAINLINK_BASE_NORMALIZATION;
  uint256 public immutable CHAINLINK_PAIRED_NORMALIZATION;
  uint256 public maxOracleDelay;
  bool public allowOnlyUniOracle;

  uint32 twapInterval = 10 minutes;

  constructor(
    address _baseToken,
    address _spTKN,
    address _pTKNBasePool,
    IV3TwapUtilities _utils,
    address _clBaseMultAddress,
    address _clBaseDivAddress,
    address _clQuoteMultAddress,
    address _clQuoteDivAddress,
    bool _allowOnlyUniOracle
  ) {
    BASE_TOKEN = _baseToken;
    SPTKN = _spTKN;
    CL_POOL = _pTKNBasePool;
    TWAP_UTILS = _utils;
    allowOnlyUniOracle = _allowOnlyUniOracle;

    address _t0 = IUniswapV3Pool(_spTKN).token0();
    address _spPairedTkn = _t0 == BASE_TOKEN
      ? IUniswapV3Pool(_spTKN).token1()
      : _t0;
    CHAINLINK_BASE_MULTIPLY_ADDRESS = _clBaseMultAddress;
    CHAINLINK_BASE_DIVIDE_ADDRESS = _clBaseDivAddress;
    CHAINLINK_BASE_NORMALIZATION = _getChainlinkNormalization(
      _baseToken,
      _spPairedTkn,
      _clBaseMultAddress,
      _clBaseDivAddress
    );
    CHAINLINK_PAIRED_MULTIPLY_ADDRESS = _clQuoteMultAddress;
    CHAINLINK_PAIRED_DIVIDE_ADDRESS = _clQuoteDivAddress;
    CHAINLINK_PAIRED_NORMALIZATION = _getChainlinkNormalization(
      _baseToken,
      _spPairedTkn,
      _clQuoteMultAddress,
      _clQuoteDivAddress
    );
  }

  function getPrices()
    public
    view
    virtual
    override
    returns (bool _isBadData, uint256 _priceLow, uint256 _priceHigh)
  {
    uint256 _priceBaseSpTKN = _calculateBasePerSpTkn(0);
    uint256 _priceOne18 = _priceBaseSpTKN *
      10 ** (18 - IERC20Metadata(BASE_TOKEN).decimals());

    uint256 _clPriceX96 = _chainlinkBasePerPairedX96();
    uint256 _clPriceBaseSpTKN = _calculateBasePerSpTkn(_clPriceX96);
    uint256 _priceTwo18 = _clPriceBaseSpTKN *
      10 ** (18 - IERC20Metadata(BASE_TOKEN).decimals());

    // If the prices are the same it means the CL price was pulled as the UniV3 price
    _isBadData = !allowOnlyUniOracle && _priceOne18 == _priceTwo18;
    _priceLow = _priceOne18 > _priceTwo18 ? _priceTwo18 : _priceOne18;
    _priceHigh = _priceOne18 > _priceTwo18 ? _priceOne18 : _priceTwo18;
  }

  function _calculateBasePerSpTkn(
    uint256 _priceX96
  ) internal view returns (uint256) {
    // pull from UniV3 TWAP if passed as 0
    if (_priceX96 == 0) {
      uint160 _sqrtPriceX96 = TWAP_UTILS.sqrtPriceX96FromPoolAndPassedInterval(
        CL_POOL,
        twapInterval
      );
      _priceX96 = TWAP_UTILS.priceX96FromSqrtPriceX96(_sqrtPriceX96);
    }
    address _pair = _getPair();
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
    (uint112 _reserve0, uint112 _reserve1, , ) = ICamelotPair(_pair)
      .getReserves();
    uint256 _k = uint256(_reserve0) * _reserve1;
    uint256 _kDec = 10 **
      IERC20Metadata(ICamelotPair(_pair).token0()).decimals() *
      10 ** IERC20Metadata(ICamelotPair(_pair).token1()).decimals();
    uint256 _avgBaseAssetInLpX96 = _sqrt((_priceAssetX96 * _k) / _kDec) *
      2 ** (96 / 2);
    uint256 _pairPriceX96 = (2 *
      _avgBaseAssetInLpX96 *
      10 ** ((_clT0Decimals + _clT1Decimals) / 2)) /
      IERC20(_pair).totalSupply();
    uint256 _baseTDecimals = _clT1 == BASE_TOKEN
      ? _clT1Decimals
      : _clT0Decimals;
    return (_pairPriceX96 * 10 ** _baseTDecimals) / FixedPoint96.Q96;
  }

  function _chainlinkBasePerPairedX96()
    internal
    view
    returns (uint256 _priceX96)
  {
    (bool _baseIsBadData, uint256 _basePrice) = _getChainlinkPrice(
      CHAINLINK_BASE_MULTIPLY_ADDRESS,
      CHAINLINK_BASE_DIVIDE_ADDRESS,
      CHAINLINK_BASE_NORMALIZATION
    );
    (bool _pairedIsBadData, uint256 _pairedPrice) = _getChainlinkPrice(
      CHAINLINK_PAIRED_MULTIPLY_ADDRESS,
      CHAINLINK_PAIRED_DIVIDE_ADDRESS,
      CHAINLINK_PAIRED_NORMALIZATION
    );
    if (_baseIsBadData || _pairedIsBadData) {
      return 0;
    }
    address _t0 = IUniswapV3Pool(SPTKN).token0();
    uint8 _t0Decimals = IERC20Metadata(_t0).decimals();
    uint8 _t1Decimals = IERC20Metadata(IUniswapV3Pool(SPTKN).token1())
      .decimals();

    // inverse than what's intuitive because prices are returns in USD/asset
    uint256 _basePerPairedX96 = (FixedPoint96.Q96 * _pairedPrice) / _basePrice;
    _priceX96 = _t0 == BASE_TOKEN
      ? (_basePerPairedX96 * 10 ** _t0Decimals) / 10 ** _t1Decimals
      : (_basePerPairedX96 * 10 ** _t1Decimals) / 10 ** _t0Decimals;
  }

  function _getChainlinkPrice(
    address _multAddress,
    address _divAddress,
    uint256 _normalization
  ) internal view returns (bool _isBadData, uint256 _price) {
    _price = uint256(1e36);

    // no CL oracle given
    if (_multAddress == address(0) && _divAddress == address(0)) {
      _isBadData = true;
      return (_isBadData, _price);
    }

    if (_multAddress != address(0)) {
      (, int256 _answer, , uint256 _updatedAt, ) = AggregatorV3Interface(
        _multAddress
      ).latestRoundData();

      // If data is stale or negative, set bad data to true and return
      if (_answer <= 0 || (block.timestamp - _updatedAt > maxOracleDelay)) {
        _isBadData = true;
        return (_isBadData, _price);
      }
      _price = _price * uint256(_answer);
    }

    if (_divAddress != address(0)) {
      (, int256 _answer, , uint256 _updatedAt, ) = AggregatorV3Interface(
        _divAddress
      ).latestRoundData();

      // If data is stale or negative, set bad data to true and return
      if (_answer <= 0 || (block.timestamp - _updatedAt > maxOracleDelay)) {
        _isBadData = true;
        return (_isBadData, _price);
      }
      _price = _price / uint256(_answer);
    }

    // return price as ratio of Collateral/Asset including decimal differences
    // _normalization = 10**(18 + asset.decimals() - collateral.decimals() + multiplyOracle.decimals() - divideOracle.decimals())
    _price = _price / _normalization;
  }

  function _getPair() private view returns (address) {
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

  function _getChainlinkNormalization(
    address _baseToken,
    address _quoteToken,
    address _multAddress,
    address _divAddress
  ) internal view returns (uint256) {
    uint8 _clMultiplyDecimals = _multAddress != address(0)
      ? AggregatorV3Interface(_multAddress).decimals()
      : 0;
    uint8 _clDivideDecimals = _divAddress != address(0)
      ? AggregatorV3Interface(_divAddress).decimals()
      : 0;
    return
      10 **
        (18 +
          _clMultiplyDecimals -
          _clDivideDecimals +
          IERC20Metadata(_baseToken).decimals() -
          IERC20Metadata(_quoteToken).decimals());
  }

  function setTwapInterval(uint32 _interval) external onlyOwner {
    twapInterval = _interval;
  }
}

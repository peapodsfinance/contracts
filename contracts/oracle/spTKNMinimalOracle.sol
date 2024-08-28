// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '../interfaces/IDecentralizedIndex.sol';
import '../interfaces/IStakingPoolToken.sol';
import '../interfaces/IUniswapV2Pair.sol';
import '../interfaces/IMinimalOracle.sol';
import '../interfaces/IMinimalSinglePriceOracle.sol';

contract spTKNMinimalOracle is IMinimalOracle, Ownable {
  /// @dev The base token we will price against in the oracle. Will be either pairedLpAsset
  /// @dev or the borrow token in a lending pair
  address public immutable BASE_TOKEN;

  /// @dev The pod stake token and oracle quote token that custodies UniV2 LP tokens
  address public immutable SP_TKN; // QUOTE_TOKEN
  address public immutable POD;

  /// @dev The concentrated liquidity UniV3 pool where we get the TWAP to price the underlying TKN
  /// @dev of the pod represented through SP_TKN and then convert it to the spTKN price
  address public immutable UNDERLYING_TKN_CL_POOL;
  address public immutable UNDERLYING_TKN;

  /// @dev The Chainlink price feed we can use to convert the price we fetch through UNDERLYING_TKN_CL_POOL
  /// @dev into a BASE_TOKEN normalized price,
  /// @dev NOTE: only needed if the paired token of the CL_POOL is not BASE_TOKEN
  address public immutable BASE_CONVERSION_CHAINLINK_FEED;
  address public immutable BASE_CONVERSION_CL_POOL;

  /// @dev Chainlink config to fetch a 2nd price for the oracle
  /// @dev The assumption would be that the paired asset of both oracles are the same
  /// @dev For example, if base=ETH, quote=BTC, the feeds we could use would be ETH/USD & BTC/USD
  address public immutable CHAINLINK_BASE_PRICE_FEED;
  address public immutable CHAINLINK_QUOTE_PRICE_FEED;

  /// @dev Single price oracle helpers to get already formatted prices that are easy to convert/use
  address public immutable CHAINLINK_SINGLE_PRICE_ORACLE;
  address public immutable UNISWAP_V3_SINGLE_PRICE_ORACLE;

  uint32 twapInterval = 10 minutes;

  constructor(
    address _baseToken,
    address _spTKN,
    address _underlyingClPool,
    address _baseConversionChainlinkFeed,
    address _baseConversionClPool,
    address _clBaseFeed,
    address _clQuoteFeed,
    address _clSinglePriceOracle,
    address _uniswapSinglePriceOracle
  ) {
    // only one (or neither) of the base conversion config should be populated
    require(
      _baseConversionChainlinkFeed == address(0) ||
        _baseConversionClPool == address(0),
      'CONV'
    );

    BASE_TOKEN = _baseToken;
    SP_TKN = _spTKN;
    UNDERLYING_TKN_CL_POOL = _underlyingClPool;
    BASE_CONVERSION_CHAINLINK_FEED = _baseConversionChainlinkFeed;
    BASE_CONVERSION_CL_POOL = _baseConversionClPool;
    CHAINLINK_BASE_PRICE_FEED = _clBaseFeed;
    CHAINLINK_QUOTE_PRICE_FEED = _clQuoteFeed;
    CHAINLINK_SINGLE_PRICE_ORACLE = _clSinglePriceOracle;
    UNISWAP_V3_SINGLE_PRICE_ORACLE = _uniswapSinglePriceOracle;

    address _pod = IStakingPoolToken(_spTKN).indexFund();
    IDecentralizedIndex.IndexAssetInfo[] memory _assets = IDecentralizedIndex(
      _pod
    ).getAllAssets();
    POD = _pod;
    UNDERLYING_TKN = _assets[0].token;
  }

  function getPrices()
    public
    view
    virtual
    override
    returns (bool _isBadData, uint256 _priceLow, uint256 _priceHigh)
  {
    uint256 _priceBaseSpTKN = _calculateBasePerSpTkn(0);
    _isBadData = _priceBaseSpTKN == 0;
    uint256 _priceOne18 = _priceBaseSpTKN *
      10 ** (18 - IERC20Metadata(BASE_TOKEN).decimals());

    uint256 _priceTwo18 = _priceOne18;
    if (CHAINLINK_BASE_PRICE_FEED != address(0)) {
      uint256 _clPrice18 = _chainlinkBasePerPaired18();
      uint256 _clPriceBaseSpTKN = _calculateBasePerSpTkn(_clPrice18);
      _priceTwo18 =
        _clPriceBaseSpTKN *
        10 ** (18 - IERC20Metadata(BASE_TOKEN).decimals());
      _isBadData = _isBadData || _clPrice18 == 0;
    }

    // If the prices are the same it means the CL price was pulled as the UniV3 price
    _priceLow = _priceOne18 > _priceTwo18 ? _priceTwo18 : _priceOne18;
    _priceHigh = _priceOne18 > _priceTwo18 ? _priceOne18 : _priceTwo18;
  }

  function _calculateBasePerSpTkn(
    uint256 _price18
  ) internal view returns (uint256 _spTknBasePrice18) {
    // pull from UniV3 TWAP if passed as 0
    if (_price18 == 0) {
      bool _isBadData;
      (_isBadData, _price18) = IMinimalSinglePriceOracle(
        UNISWAP_V3_SINGLE_PRICE_ORACLE
      ).getPriceUSD18(
          BASE_CONVERSION_CHAINLINK_FEED,
          UNDERLYING_TKN,
          UNDERLYING_TKN_CL_POOL,
          twapInterval
        );
      if (_isBadData) {
        return 0;
      }

      if (BASE_CONVERSION_CL_POOL != address(0)) {
        (
          bool _subBadData,
          uint256 _baseConvPrice18
        ) = IMinimalSinglePriceOracle(UNISWAP_V3_SINGLE_PRICE_ORACLE)
            .getPriceUSD18(
              address(0),
              BASE_TOKEN,
              BASE_CONVERSION_CL_POOL,
              twapInterval
            );
        if (_subBadData) {
          return 0;
        }
        _price18 = (10 ** 18 * _baseConvPrice18) / _price18;
      }
    }
    address _pair = _getPair();
    address _clT0 = IUniswapV2Pair(UNDERLYING_TKN_CL_POOL).token0();
    uint8 _clT0Decimals = IERC20Metadata(_clT0).decimals();
    address _clT1 = IUniswapV2Pair(UNDERLYING_TKN_CL_POOL).token1();
    uint8 _clT1Decimals = IERC20Metadata(_clT1).decimals();
    uint256 _pricePTKNPerBase18 = _clT1 == BASE_TOKEN
      ? _accountForCBR(_price18)
      : 10 ** (18 * 2) / _accountForCBR(_price18);
    // (uint112 _reserve0, uint112 _reserve1, , ) = ICamelotPair(_pair)
    //   .getReserves();
    (uint112 _reserve0, uint112 _reserve1, ) = IUniswapV2Pair(_pair)
      .getReserves();
    uint256 _k = uint256(_reserve0) * _reserve1;
    uint256 _kDec = 10 **
      IERC20Metadata(IUniswapV2Pair(_pair).token0()).decimals() *
      10 ** IERC20Metadata(IUniswapV2Pair(_pair).token1()).decimals();
    uint256 _avgBaseAssetInLp18 = _sqrt((_pricePTKNPerBase18 * _k) / _kDec) *
      10 ** (18 / 2);
    uint256 _pairPrice18 = (2 *
      _avgBaseAssetInLp18 *
      10 ** ((_clT0Decimals + _clT1Decimals) / 2)) /
      IERC20(_pair).totalSupply();
    uint256 _baseTDecimals = _clT1 == BASE_TOKEN
      ? _clT1Decimals
      : _clT0Decimals;
    _spTknBasePrice18 = (_pairPrice18 * 10 ** _baseTDecimals) / 10 ** 18;
  }

  function _chainlinkBasePerPaired18()
    internal
    view
    returns (uint256 _price18)
  {
    (bool _isBadData, uint256 _basePerPaired18) = IMinimalSinglePriceOracle(
      CHAINLINK_SINGLE_PRICE_ORACLE
    ).getPriceUSD18(
        CHAINLINK_QUOTE_PRICE_FEED,
        CHAINLINK_BASE_PRICE_FEED,
        address(0),
        0
      );
    if (_isBadData) {
      return 0;
    }
    _price18 = _basePerPaired18;
  }

  function _getPair() private view returns (address) {
    return IStakingPoolToken(SP_TKN).stakingToken();
  }

  function _accountForCBR(
    uint256 _amtUnderlying
  ) internal view returns (uint256) {
    return
      (_amtUnderlying *
        IERC20(UNDERLYING_TKN).balanceOf(POD) *
        10 ** IERC20Metadata(POD).decimals()) /
      IERC20(POD).totalSupply() /
      10 ** IERC20Metadata(UNDERLYING_TKN).decimals();
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

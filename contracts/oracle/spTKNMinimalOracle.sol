// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '../interfaces/IDecentralizedIndex.sol';
import '../interfaces/IStakingPoolToken.sol';
import '../interfaces/IUniswapV2Pair.sol';
import '../interfaces/IMinimalOracle.sol';
import '../interfaces/IMinimalSinglePriceOracle.sol';
import '../interfaces/IV2Reserves.sol';

contract spTKNMinimalOracle is IMinimalOracle, Ownable {
  /// @dev The base token we will price against in the oracle. Will be either pairedLpAsset
  /// @dev or the borrow token in a lending pair
  address public immutable BASE_TOKEN;
  bool public immutable BASE_IS_POD;

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

  /// @dev Different networks will use different forked implementations of UniswapV2, so
  /// @dev this allows us to define a uniform interface to fetch the reserves of each asset in a pair
  IV2Reserves public immutable V2_RESERVES;

  uint32 twapInterval = 10 minutes;

  constructor(
    address _baseToken,
    bool _baseIsPod,
    address _spTKN,
    address _underlyingClPool,
    address _baseConversionChainlinkFeed,
    address _baseConversionClPool,
    address _clBaseFeed,
    address _clQuoteFeed,
    address _clSinglePriceOracle,
    address _uniswapSinglePriceOracle,
    address _v2Reserves
  ) {
    // only one (or neither) of the base conversion config should be populated
    require(
      _baseConversionChainlinkFeed == address(0) ||
        _baseConversionClPool == address(0),
      'CONV'
    );

    BASE_TOKEN = _baseToken;
    BASE_IS_POD = _baseIsPod;
    SP_TKN = _spTKN;
    UNDERLYING_TKN_CL_POOL = _underlyingClPool;
    BASE_CONVERSION_CHAINLINK_FEED = _baseConversionChainlinkFeed;
    BASE_CONVERSION_CL_POOL = _baseConversionClPool;
    CHAINLINK_BASE_PRICE_FEED = _clBaseFeed;
    CHAINLINK_QUOTE_PRICE_FEED = _clQuoteFeed;
    CHAINLINK_SINGLE_PRICE_ORACLE = _clSinglePriceOracle;
    UNISWAP_V3_SINGLE_PRICE_ORACLE = _uniswapSinglePriceOracle;
    V2_RESERVES = IV2Reserves(_v2Reserves);

    address _pod = IStakingPoolToken(_spTKN).indexFund();
    IDecentralizedIndex.IndexAssetInfo[] memory _assets = IDecentralizedIndex(
      _pod
    ).getAllAssets();
    POD = _pod;
    UNDERLYING_TKN = _assets[0].token;
  }

  /// @notice The ```getPrices``` function gets the mathematical price of SP_TKN / BASE_TOKEN, so in plain english will
  /// @notice be the number of SP_TKN per every BASE_TOKEN
  /// @return _isBadData Whether the price(s) returned should be considered bad
  /// @return _priceLow The lower of the dual prices returned
  /// @return _priceHigh The higher of the dual prices returned
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
    if (
      CHAINLINK_BASE_PRICE_FEED != address(0) &&
      CHAINLINK_QUOTE_PRICE_FEED != address(0)
    ) {
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
    address _baseInCl = _getBaseTokenInClPool();
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
              _baseInCl,
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
    address _clT1 = IUniswapV2Pair(UNDERLYING_TKN_CL_POOL).token1();
    uint256 _pricePTKNPerBase18 = _clT1 == _baseInCl
      ? _accountForCBRInPrice(POD, UNDERLYING_TKN, _price18)
      : 10 ** (18 * 2) / _accountForCBRInPrice(POD, UNDERLYING_TKN, _price18);

    // adjust current price for spTKN pod unwrap fee, which will end up making the end price
    // (spTKN per base) higher, meaning it will take more spTKN to equal the value
    // of base token. This will more accurately ensure healthy LTVs when lending since
    // a liquidation path will need to account for unwrap fees
    _pricePTKNPerBase18 = _accountForUnwrapFeeInPrice(POD, _pricePTKNPerBase18);

    (uint112 _reserve0, uint112 _reserve1) = V2_RESERVES.getReserves(_pair);
    uint256 _k = uint256(_reserve0) * _reserve1;
    uint256 _kDec = 10 **
      IERC20Metadata(IUniswapV2Pair(_pair).token0()).decimals() *
      10 ** IERC20Metadata(IUniswapV2Pair(_pair).token1()).decimals();
    uint256 _avgBaseAssetInLp18 = _sqrt((_pricePTKNPerBase18 * _k) / _kDec) *
      10 ** (18 / 2);
    uint256 _basePerSpTkn18 = (2 * _avgBaseAssetInLp18 * 10 ** 18) /
      IERC20(_pair).totalSupply();
    _spTknBasePrice18 = 10 ** (18 * 2) / _basePerSpTkn18;

    // if the base asset is a pod, we will assume that the CL/chainlink pool(s) are
    // pricing the underlying asset of the base asset pod, and therefore we will
    // adjust the output price by CBR and unwrap fee for this pod for more accuracy and
    // better handling accounting for liquidation path
    if (BASE_IS_POD) {
      _spTknBasePrice18 = _checkAndHandleBaseTokenPodConfig(_spTknBasePrice18);
    }
  }

  function _getBaseTokenInClPool() internal view returns (address _base) {
    _base = BASE_TOKEN;
    if (BASE_IS_POD) {
      IDecentralizedIndex.IndexAssetInfo[]
        memory _baseAssets = IDecentralizedIndex(BASE_TOKEN).getAllAssets();
      _base = _baseAssets[0].token;
    }
  }

  function _checkAndHandleBaseTokenPodConfig(
    uint256 _currentPrice18
  ) internal view returns (uint256 _finalPrice18) {
    _finalPrice18 = _accountForCBRInPrice(
      BASE_TOKEN,
      address(0),
      _currentPrice18
    );
    _finalPrice18 = _accountForUnwrapFeeInPrice(BASE_TOKEN, _finalPrice18);
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

  function _accountForCBRInPrice(
    address _pod,
    address _underlying,
    uint256 _amtUnderlying
  ) internal view returns (uint256) {
    require(IDecentralizedIndex(_pod).unlocked() == 1, 'OU');
    if (_underlying == address(0)) {
      IDecentralizedIndex.IndexAssetInfo[] memory _assets = IDecentralizedIndex(
        _pod
      ).getAllAssets();
      _underlying = _assets[0].token;
    }
    return
      (_amtUnderlying *
        IERC20(_underlying).balanceOf(_pod) *
        10 ** IERC20Metadata(_pod).decimals()) /
      IERC20(_pod).totalSupply() /
      10 ** IERC20Metadata(_underlying).decimals();
  }

  function _accountForUnwrapFeeInPrice(
    address _pod,
    uint256 _currentPrice
  ) internal view returns (uint256 _newPrice) {
    uint16 _unwrapFee = IDecentralizedIndex(_pod).DEBOND_FEE();
    _newPrice = _currentPrice - (_currentPrice * _unwrapFee) / 10000;
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

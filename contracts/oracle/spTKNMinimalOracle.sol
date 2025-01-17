// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/IDecentralizedIndex.sol";
import "../interfaces/IFraxlendPair.sol";
import "../interfaces/IStakingPoolToken.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IMinimalOracle.sol";
import "../interfaces/ISPTknOracle.sol";
import "../interfaces/IMinimalSinglePriceOracle.sol";
import "../interfaces/IV2Reserves.sol";

contract spTKNMinimalOracle is IMinimalOracle, ISPTknOracle, Ownable {
    /// @dev The base token we will price against in the oracle. Will be either pairedLpAsset
    /// @dev or the borrow token in a lending pair
    address public immutable BASE_TOKEN;
    bool public immutable BASE_IS_POD;
    bool public immutable BASE_IS_FRAX_PAIR;
    address internal immutable BASE_IN_CL;

    /// @dev The concentrated liquidity UniV3 pool where we get the TWAP to price the underlying TKN
    /// @dev of the pod represented through spTkn and then convert it to the spTKN price
    address public immutable UNDERLYING_TKN_CL_POOL;

    /// @dev The Chainlink price feed we can use to convert the price we fetch through UNDERLYING_TKN_CL_POOL
    /// @dev into a BASE_TOKEN normalized price,
    /// @dev NOTE: primarily only needed if the paired token of the CL_POOL is not BASE_TOKEN
    address public immutable BASE_CONVERSION_CHAINLINK_FEED;
    address public immutable BASE_CONVERSION_CL_POOL;
    address public immutable BASE_CONVERSION_DIA_FEED;

    /// @dev Chainlink config to fetch a 2nd price for the oracle
    /// @dev The assumption would be that the paired asset of both oracles are the same
    /// @dev For example, if base=ETH, quote=BTC, the feeds we could use would be ETH/USD & BTC/USD
    address public immutable CHAINLINK_BASE_PRICE_FEED;
    address public immutable CHAINLINK_QUOTE_PRICE_FEED;

    /// @dev Single price oracle helpers to get already formatted prices that are easy to convert/use
    address public immutable CHAINLINK_SINGLE_PRICE_ORACLE;
    address public immutable UNISWAP_V3_SINGLE_PRICE_ORACLE;
    address public immutable DIA_SINGLE_PRICE_ORACLE;

    /// @dev Different networks will use different forked implementations of UniswapV2, so
    /// @dev this allows us to define a uniform interface to fetch the reserves of each asset in a pair
    IV2Reserves public immutable V2_RESERVES;

    /// @dev The pod staked LP token and oracle quote token that custodies UniV2 LP tokens
    address public spTkn; // QUOTE_TOKEN
    address public pod;
    address public underlyingTkn;

    uint32 twapInterval = 10 minutes;

    event SetSpTknAndDependencies(address _pod);

    event SetTwapInterval(uint32 oldMax, uint32 newMax);

    constructor(bytes memory _requiredImmutables, bytes memory _optionalImmutables) Ownable(_msgSender()) {
        address _spTkn;
        address _v2Reserves;
        (
            CHAINLINK_SINGLE_PRICE_ORACLE,
            UNISWAP_V3_SINGLE_PRICE_ORACLE,
            DIA_SINGLE_PRICE_ORACLE,
            BASE_TOKEN,
            BASE_IS_POD,
            BASE_IS_FRAX_PAIR,
            _spTkn,
            UNDERLYING_TKN_CL_POOL
        ) = abi.decode(_requiredImmutables, (address, address, address, address, bool, bool, address, address));
        (
            BASE_CONVERSION_CHAINLINK_FEED,
            BASE_CONVERSION_CL_POOL,
            BASE_CONVERSION_DIA_FEED,
            CHAINLINK_BASE_PRICE_FEED,
            CHAINLINK_QUOTE_PRICE_FEED,
            _v2Reserves
        ) = abi.decode(_optionalImmutables, (address, address, address, address, address, address));
        V2_RESERVES = IV2Reserves(_v2Reserves);

        // only one (or neither) of the base conversion config should be populated
        address _baseConvFinal =
            BASE_CONVERSION_DIA_FEED != address(0) ? BASE_CONVERSION_DIA_FEED : BASE_CONVERSION_CL_POOL;
        require(BASE_CONVERSION_CHAINLINK_FEED == address(0) || _baseConvFinal == address(0), "CONV");

        if (CHAINLINK_QUOTE_PRICE_FEED != address(0)) {
            require(CHAINLINK_BASE_PRICE_FEED != address(0), "BCLF");
        }

        address _baseInCl = BASE_TOKEN;
        if (BASE_IS_POD) {
            IDecentralizedIndex.IndexAssetInfo[] memory _baseAssets = IDecentralizedIndex(BASE_TOKEN).getAllAssets();
            _baseInCl = _baseAssets[0].token;
        } else if (BASE_IS_FRAX_PAIR) {
            _baseInCl = IFraxlendPair(BASE_TOKEN).asset();
        }
        BASE_IN_CL = _baseInCl;

        _setSpTknAndDependencies(_spTkn);
    }

    function getPodPerBasePrice() external view override returns (uint256 _pricePTknPerBase18) {
        _pricePTknPerBase18 = 10 ** (18 * 2) / _calculateBasePerPTkn(0);
    }

    /// @notice The ```getPrices``` function gets the mathematical price of spTkn / BASE_TOKEN, so in plain english will
    /// @notice be the number of spTkn per every BASE_TOKEN at 1e18 precision
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
        uint256 _priceSpTKNBase = _calculateSpTknPerBase(0);
        _isBadData = _priceSpTKNBase == 0;
        uint8 _baseDec = IERC20Metadata(BASE_TOKEN).decimals();
        uint256 _priceOne18 = _priceSpTKNBase * 10 ** (_baseDec > 18 ? _baseDec - 18 : 18 - _baseDec);

        uint256 _priceTwo18 = _priceOne18;
        if (CHAINLINK_BASE_PRICE_FEED != address(0) && CHAINLINK_QUOTE_PRICE_FEED != address(0)) {
            uint256 _clPrice18 = _chainlinkBasePerPaired18();
            uint256 _clPriceBaseSpTKN = _calculateSpTknPerBase(_clPrice18);
            _priceTwo18 = _clPriceBaseSpTKN * 10 ** (_baseDec > 18 ? _baseDec - 18 : 18 - _baseDec);
            _isBadData = _isBadData || _clPrice18 == 0;
        }

        require(_priceOne18 != 0 || _priceTwo18 != 0, "BZ");

        if (_priceTwo18 == 0) {
            _priceLow = _priceOne18;
            _priceHigh = _priceOne18;
        } else {
            // If the prices are the same it means the CL price was pulled as the UniV3 price
            (_priceLow, _priceHigh) =
                _priceOne18 > _priceTwo18 ? (_priceTwo18, _priceOne18) : (_priceOne18, _priceTwo18);
        }
    }

    function _calculateSpTknPerBase(uint256 _price18) internal view returns (uint256 _spTknBasePrice18) {
        uint256 _priceBasePerPTkn18 = _calculateBasePerPTkn(_price18);
        address _pair = _getPair();

        (uint112 _reserve0, uint112 _reserve1) = V2_RESERVES.getReserves(_pair);
        uint256 _k = uint256(_reserve0) * _reserve1;
        uint256 _kDec = 10 ** IERC20Metadata(IUniswapV2Pair(_pair).token0()).decimals()
            * 10 ** IERC20Metadata(IUniswapV2Pair(_pair).token1()).decimals();
        uint256 _avgBaseAssetInLp18 = _sqrt((_priceBasePerPTkn18 * _k) / _kDec) * 10 ** (18 / 2);
        uint256 _basePerSpTkn18 =
            (2 * _avgBaseAssetInLp18 * 10 ** IERC20Metadata(_pair).decimals()) / IERC20(_pair).totalSupply();
        require(_basePerSpTkn18 > 0, "V2R");
        _spTknBasePrice18 = 10 ** (18 * 2) / _basePerSpTkn18;

        // if the base asset is a pod, we will assume that the CL/chainlink pool(s) are
        // pricing the underlying asset of the base asset pod, and therefore we will
        // adjust the output price by CBR and unwrap fee for this pod for more accuracy and
        // better handling accounting for liquidation path
        if (BASE_IS_POD) {
            _spTknBasePrice18 = _checkAndHandleBaseTokenPodConfig(_spTknBasePrice18);
        } else if (BASE_IS_FRAX_PAIR) {
            _spTknBasePrice18 = IFraxlendPair(BASE_TOKEN).convertToAssets(_spTknBasePrice18);
        }
    }

    function _calculateBasePerPTkn(uint256 _price18) internal view returns (uint256 _basePerPTkn18) {
        // pull from UniV3 TWAP if passed as 0
        if (_price18 == 0) {
            bool _isBadData;
            (_isBadData, _price18) = _getDefaultPrice18();
            if (_isBadData) {
                return 0;
            }
        }
        _basePerPTkn18 = _accountForCBRInPrice(pod, underlyingTkn, _price18);

        // adjust current price for spTKN pod unwrap fee, which will end up making the end price
        // (spTKN per base) higher, meaning it will take more spTKN to equal the value
        // of base token. This will more accurately ensure healthy LTVs when lending since
        // a liquidation path will need to account for unwrap fees
        _basePerPTkn18 = _accountForUnwrapFeeInPrice(pod, _basePerPTkn18);
    }

    function _getDefaultPrice18() internal view returns (bool _isBadData, uint256 _price18) {
        (_isBadData, _price18) = IMinimalSinglePriceOracle(UNISWAP_V3_SINGLE_PRICE_ORACLE).getPriceUSD18(
            BASE_CONVERSION_CHAINLINK_FEED, underlyingTkn, UNDERLYING_TKN_CL_POOL, twapInterval
        );
        if (_isBadData) {
            return (true, 0);
        }

        if (BASE_CONVERSION_DIA_FEED != address(0)) {
            (bool _subBadData, uint256 _baseConvPrice18) = IMinimalSinglePriceOracle(DIA_SINGLE_PRICE_ORACLE)
                .getPriceUSD18(address(0), BASE_IN_CL, BASE_CONVERSION_DIA_FEED, 0);
            if (_subBadData) {
                return (true, 0);
            }
            _price18 = (10 ** 18 * _price18) / _baseConvPrice18;
        } else if (BASE_CONVERSION_CL_POOL != address(0)) {
            (bool _subBadData, uint256 _baseConvPrice18) = IMinimalSinglePriceOracle(UNISWAP_V3_SINGLE_PRICE_ORACLE)
                .getPriceUSD18(address(0), BASE_IN_CL, BASE_CONVERSION_CL_POOL, twapInterval);
            if (_subBadData) {
                return (true, 0);
            }
            _price18 = (10 ** 18 * _price18) / _baseConvPrice18;
        }
    }

    function _checkAndHandleBaseTokenPodConfig(uint256 _currentPrice18) internal view returns (uint256 _finalPrice18) {
        _finalPrice18 = _accountForCBRInPrice(BASE_TOKEN, address(0), _currentPrice18);
        _finalPrice18 = _accountForUnwrapFeeInPrice(BASE_TOKEN, _finalPrice18);
    }

    function _chainlinkBasePerPaired18() internal view returns (uint256 _price18) {
        (bool _isBadData, uint256 _basePerPaired18) = IMinimalSinglePriceOracle(CHAINLINK_SINGLE_PRICE_ORACLE)
            .getPriceUSD18(CHAINLINK_QUOTE_PRICE_FEED, CHAINLINK_BASE_PRICE_FEED, address(0), 0);
        if (_isBadData) {
            return 0;
        }
        _price18 = _basePerPaired18;
    }

    function _getPair() private view returns (address) {
        return IStakingPoolToken(spTkn).stakingToken();
    }

    function _accountForCBRInPrice(address _pod, address _underlying, uint256 _amtUnderlying)
        internal
        view
        returns (uint256)
    {
        require(IDecentralizedIndex(_pod).unlocked() == 1, "OU");
        if (_underlying == address(0)) {
            IDecentralizedIndex.IndexAssetInfo[] memory _assets = IDecentralizedIndex(_pod).getAllAssets();
            _underlying = _assets[0].token;
        }
        uint256 _pTknAmt =
            (_amtUnderlying * 10 ** IERC20Metadata(_pod).decimals()) / 10 ** IERC20Metadata(_underlying).decimals();
        return IDecentralizedIndex(_pod).convertToAssets(_pTknAmt);
    }

    function _accountForUnwrapFeeInPrice(address _pod, uint256 _currentPrice)
        internal
        view
        returns (uint256 _newPrice)
    {
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

    function _setSpTknAndDependencies(address _spTkn) internal {
        if (address(_spTkn) == address(0)) {
            return;
        }
        require(address(spTkn) == address(0), "S");
        spTkn = _spTkn;
        pod = IStakingPoolToken(spTkn).INDEX_FUND();
        IDecentralizedIndex.IndexAssetInfo[] memory _assets = IDecentralizedIndex(pod).getAllAssets();
        underlyingTkn = _assets[0].token;
        emit SetSpTknAndDependencies(address(pod));
    }

    function setSpTknAndDependencies(address _spTkn) external onlyOwner {
        require(address(_spTkn) != address(0), "INP");
        _setSpTknAndDependencies(_spTkn);
    }

    function setTwapInterval(uint32 _interval) external onlyOwner {
        require(_interval > 0, "Z");
        uint32 _oldInterval = twapInterval;
        twapInterval = _interval;
        emit SetTwapInterval(_oldInterval, _interval);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "../interfaces/IDIAOracleV2.sol";
import "./ChainlinkSinglePriceOracle.sol";

contract DIAOracleV2SinglePriceOracle is ChainlinkSinglePriceOracle {
    uint256 public staleAfterLastRefresh = 60 minutes;

    constructor(address _sequencer) ChainlinkSinglePriceOracle(_sequencer) {}

    function getPriceUSD18(
        address _clBaseConversionPoolPriceFeed,
        address _quoteToken,
        address _quoteDIAOracle,
        uint256
    ) external view virtual override returns (bool _isBadData, uint256 _price18) {
        string memory _symbol = IERC20Metadata(_quoteToken).symbol();
        (uint128 _quotePrice8, uint128 _refreshedLast) =
            IDIAOracleV2(_quoteDIAOracle).getValue(string.concat(_symbol, "/USD"));
        if (_refreshedLast + staleAfterLastRefresh < block.timestamp) {
            _isBadData = true;
        }

        // default base price to 1, which just means return only quote pool price without any base conversion
        uint256 _basePrice18 = 10 ** 18;
        uint256 _updatedAt = block.timestamp;
        bool _isBadDataBase;
        if (_clBaseConversionPoolPriceFeed != address(0)) {
            (_basePrice18, _updatedAt, _isBadDataBase) = _getChainlinkPriceFeedPrice18(_clBaseConversionPoolPriceFeed);
            uint256 _maxDelayBase = feedMaxOracleDelay[_clBaseConversionPoolPriceFeed] > 0
                ? feedMaxOracleDelay[_clBaseConversionPoolPriceFeed]
                : defaultMaxOracleDelay;
            uint256 _isBadTimeBase = block.timestamp - _maxDelayBase;
            _isBadData = _isBadData || _isBadDataBase || _updatedAt < _isBadTimeBase;
        }
        _price18 = (_quotePrice8 * _basePrice18) / 10 ** 8;
    }

    function setStaleAfterLastRefresh(uint256 _seconds) external onlyOwner {
        staleAfterLastRefresh = _seconds;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol';
import '../interfaces/IMinimalSinglePriceOracle.sol';

contract ChainlinkSinglePriceOracle is IMinimalSinglePriceOracle, Ownable {
  event SetMaxOracleDelay(uint256 _oldDelay, uint256 _newDelay);

  uint256 public maxOracleDelay = 1 days;

  /// @notice The ```getPriceUSD18``` function gets the QUOTE/BASE price (mathematically BASE per QUOTE)
  /// @param _priceFeedQuote Chainlink price feed representing the quote token, probably quote/USD (mathematically USD per quote)
  /// @param _priceFeedBase Chainlink price feed representing the base token, probably quote/USD (mathematically USD per base)
  /// @return _isBadData Whether the oracle is returning what we should assume is bad data
  /// @return _price18 Number representing the price with 1e18 precision
  function getPriceUSD18(
    address _priceFeedQuote,
    address _priceFeedBase,
    address,
    uint256
  ) external view virtual override returns (bool _isBadData, uint256 _price18) {
    uint256 _quoteUpdatedAt;
    uint256 _isBadTime = block.timestamp - maxOracleDelay;
    (_price18, _quoteUpdatedAt) = _getChainlinkPriceFeedPrice18(
      _priceFeedQuote
    );
    _isBadData = _quoteUpdatedAt < _isBadTime;
    if (_priceFeedBase != address(0)) {
      (
        uint256 _basePrice18,
        uint256 _baseUpdatedAt
      ) = _getChainlinkPriceFeedPrice18(_priceFeedBase);
      _price18 = (10 ** 18 * _price18) / _basePrice18;
      _isBadData = _isBadData || _baseUpdatedAt < _isBadTime;
    }
  }

  function _getChainlinkPriceFeedPrice18(
    address _priceFeed
  ) internal view returns (uint256 _price18, uint256 _updatedAt) {
    uint8 _decimals = AggregatorV3Interface(_priceFeed).decimals();
    (, int256 _price, , uint256 _lastUpdated, ) = AggregatorV3Interface(
      _priceFeed
    ).latestRoundData();
    _price18 = uint256(_price) * (10 ** 18 / 10 ** _decimals);
    _updatedAt = _lastUpdated;
  }

  function setMaxOracleDelay(uint256 _newDelaySeconds) external onlyOwner {
    uint256 _current = maxOracleDelay;
    maxOracleDelay = _newDelaySeconds;
    emit SetMaxOracleDelay(_current, _newDelaySeconds);
  }
}

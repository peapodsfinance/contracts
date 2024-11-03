// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/interfaces/IERC4626.sol';
import './spTKNMinimalOracle.sol';

contract aspTKNMinimalOracle is spTKNMinimalOracle {
  address public immutable ASP_TKN; // QUOTE_TOKEN

  constructor(
    address _aspTKN,
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
  )
    spTKNMinimalOracle(
      _baseToken,
      _baseIsPod,
      _spTKN,
      _underlyingClPool,
      _baseConversionChainlinkFeed,
      _baseConversionClPool,
      _clBaseFeed,
      _clQuoteFeed,
      _clSinglePriceOracle,
      _uniswapSinglePriceOracle,
      _v2Reserves
    )
  {
    ASP_TKN = _aspTKN;
  }

  function getPrices()
    public
    view
    virtual
    override
    returns (bool _isBadData, uint256 _priceLow, uint256 _priceHigh)
  {
    uint256 _assetFactor = 10 ** 18;
    uint256 _aspTknPerSpTkn = IERC4626(ASP_TKN).convertToShares(_assetFactor);
    (_isBadData, _priceLow, _priceHigh) = super.getPrices();
    if (_priceLow == 0 && _priceHigh == 0) assert(false);
    _priceLow = (_priceLow * _aspTknPerSpTkn) / _assetFactor;
    _priceHigh = (_priceHigh * _aspTknPerSpTkn) / _assetFactor;
    if (_priceLow == 0) _priceLow = 1e18;
    if (_priceHigh == 0) _priceHigh = 1e18;
  }
}

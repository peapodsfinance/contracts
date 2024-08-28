// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/interfaces/IERC4626.sol';
import './spTKNMinimalOracle.sol';

contract aspTKNMinimalOracle is spTKNMinimalOracle {
  address public immutable ASP_TKN; // QUOTE_TOKEN

  constructor(
    address _aspTKN,
    address _baseToken,
    address _spTKN,
    address _underlyingClPool,
    address _baseConversionChainlinkFeed,
    address _baseConversionClPool,
    address _clBaseFeed,
    address _clQuoteFeed,
    address _clSinglePriceOracle,
    address _uniswapSinglePriceOracle
  )
    spTKNMinimalOracle(
      _baseToken,
      _spTKN,
      _underlyingClPool,
      _baseConversionChainlinkFeed,
      _baseConversionClPool,
      _clBaseFeed,
      _clQuoteFeed,
      _clSinglePriceOracle,
      _uniswapSinglePriceOracle
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
    _priceLow = (_priceLow * _assetFactor) / _aspTknPerSpTkn;
    _priceHigh = (_priceHigh * _assetFactor) / _aspTknPerSpTkn;
  }
}

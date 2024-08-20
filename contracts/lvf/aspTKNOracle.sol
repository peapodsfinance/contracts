// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/interfaces/IERC4626.sol';
import './spTKNOracle.sol';

contract aspTKNOracle is spTKNOracle {
  address public immutable ASPTKN; // QUOTE_TOKEN

  constructor(
    address _aspTKN,
    address _baseToken,
    address _spTKN,
    address _pTKNBasePool,
    IV3TwapUtilities _utils,
    address _clBaseMultAddress,
    address _clBaseDivAddress,
    address _clQuoteMultAddress,
    address _clQuoteDivAddress,
    bool _allowOnlyUniOracle
  )
    spTKNOracle(
      _baseToken,
      _spTKN,
      _pTKNBasePool,
      _utils,
      _clBaseMultAddress,
      _clBaseDivAddress,
      _clQuoteMultAddress,
      _clQuoteDivAddress,
      _allowOnlyUniOracle
    )
  {
    ASPTKN = _aspTKN;
  }

  function getPrices()
    public
    view
    virtual
    override
    returns (bool _isBadData, uint256 _priceLow, uint256 _priceHigh)
  {
    uint256 _assetFactor = 10 ** 18;
    uint256 _aspTknPerSpTkn = IERC4626(ASPTKN).convertToShares(_assetFactor);
    (_isBadData, _priceLow, _priceHigh) = super.getPrices();
    _priceLow = (_priceLow * _assetFactor) / _aspTknPerSpTkn;
    _priceHigh = (_priceHigh * _assetFactor) / _aspTknPerSpTkn;
  }
}

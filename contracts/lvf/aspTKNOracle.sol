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
    address _clMultAddress,
    address _clDivAddress,
    bool _allowOnlyUniOracle
  )
    spTKNOracle(
      _baseToken,
      _spTKN,
      _pTKNBasePool,
      _utils,
      _clMultAddress,
      _clDivAddress,
      _allowOnlyUniOracle
    )
  {
    ASPTKN = _aspTKN;
  }

  function getPrices()
    external
    view
    virtual
    override
    returns (bool _isBadData, uint256 _priceLow, uint256 _priceHigh)
  {
    uint256 _assetFactor = 10 ** 18;
    uint256 _aspTknPerSpTkn = IERC4626(ASPTKN).convertToShares(_assetFactor);
    uint256 _priceBaseAspTKNX96 = (_v3BasePerSpTKNX96() * _assetFactor) /
      _aspTknPerSpTkn;

    uint256 _priceMid18 = (_priceBaseAspTKNX96 * 10 ** 18) / FixedPoint96.Q96;
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
}

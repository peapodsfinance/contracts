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
    IV3TwapUtilities _utils
  ) spTKNOracle(_baseToken, _spTKN, _pTKNBasePool, _utils) {
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
    uint256 _priceBaseAspTKNX96 = (_basePerSpTKNX96() * _assetFactor) /
      _aspTknPerSpTkn;

    _isBadData = false;
    uint256 _priceMid = (_priceBaseAspTKNX96 * 10 ** 18) / FixedPoint96.Q96;
    _priceLow = (_priceMid * 99) / 100;
    _priceHigh = (_priceMid * 101) / 100;
  }
}

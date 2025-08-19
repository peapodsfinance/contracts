// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../interfaces/IDIAOracleV2.sol";

contract DIAMultiFeedConverter is IDIAOracleV2 {
    uint256 public staleAfterLastRefresh = 60 minutes;

    address immutable MAIN_DIA_FEED;
    string NUMERATOR_SYMBOL;
    string DENOMENATOR_SYMBOL;

    constructor(address _mainDiaFeed, string memory _numeratorSymbol, string memory _denomenatorSymbol) {
        MAIN_DIA_FEED = _mainDiaFeed;
        NUMERATOR_SYMBOL = _numeratorSymbol;
        DENOMENATOR_SYMBOL = _denomenatorSymbol;
    }

    function getValue(string memory) external view virtual override returns (uint128 price8, uint128 _refreshedLast) {
        (uint128 _numPrice8, uint128 _refreshedLastNum) =
            IDIAOracleV2(MAIN_DIA_FEED).getValue(string.concat(NUMERATOR_SYMBOL, "/USD"));
        (uint128 _denPrice8, uint128 _refreshedLastDen) =
            IDIAOracleV2(MAIN_DIA_FEED).getValue(string.concat(DENOMENATOR_SYMBOL, "/USD"));

        price8 = (10 ** 8 * _denPrice8) / _numPrice8;
        // return the oldest refresh time for staleness
        _refreshedLast = _refreshedLastNum < _refreshedLastDen ? _refreshedLastNum : _refreshedLastDen;
    }
}

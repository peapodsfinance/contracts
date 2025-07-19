// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "../interfaces/IDIAOracleV2.sol";
import "./ChainlinkSinglePriceOracle.sol";

contract DIAMultiFeedConverter is ChainlinkSinglePriceOracle {
    uint256 public staleAfterLastRefresh = 60 minutes;

    string NUMERATOR_SYMBOL;
    string DENOMENATOR_SYMBOL;

    constructor(address _sequencer, string memory _numeratorSymbol, string memory _denomenatorSymbol)
        ChainlinkSinglePriceOracle(_sequencer)
    {
        NUMERATOR_SYMBOL = _numeratorSymbol;
        DENOMENATOR_SYMBOL = _denomenatorSymbol;
    }

    function getPriceUSD18(address, address, address _quoteDIAOracle, uint256)
        external
        view
        virtual
        override
        returns (bool _isBadData, uint256 _price18)
    {
        (uint128 _numPrice8, uint128 _refreshedLastNum) =
            IDIAOracleV2(_quoteDIAOracle).getValue(string.concat(NUMERATOR_SYMBOL, "/USD"));
        (uint128 _denPrice8, uint128 _refreshedLastDen) =
            IDIAOracleV2(_quoteDIAOracle).getValue(string.concat(DENOMENATOR_SYMBOL, "/USD"));
        if (
            _refreshedLastNum + staleAfterLastRefresh < block.timestamp
                || _refreshedLastDen + staleAfterLastRefresh < block.timestamp
        ) {
            _isBadData = true;
        }

        _price18 = (10 ** 8 * _denPrice8) / _numPrice8;
    }

    function setStaleAfterLastRefresh(uint256 _seconds) external onlyOwner {
        staleAfterLastRefresh = _seconds;
    }
}

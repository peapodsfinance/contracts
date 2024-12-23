// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IStaticOracle} from "@mean-finance/uniswap-v3-oracle/solidity/interfaces/IStaticOracle.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MockDualOracle {
    uint128 public constant ORACLE_PRECISION = 1e18;
    uint8 internal constant DECIMALS = 18;

    /// @notice The ```getPrices``` function is intended to return two prices from different oracles
    /// @return _isBadData is true when chainlink data is stale or negative
    /// @return _priceLow is the lower of the two prices
    /// @return _priceHigh is the higher of the two prices
    function getPrices() external pure returns (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) {
        return (false, 0.5e18, 0.5e18);
    }

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }
}

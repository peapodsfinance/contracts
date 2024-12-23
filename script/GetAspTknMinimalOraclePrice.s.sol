// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/oracle/ChainlinkSinglePriceOracle.sol";
import "../contracts/oracle/UniswapV3SinglePriceOracle.sol";
import "../contracts/oracle/V2ReservesUniswap.sol";
import {DIAOracleV2SinglePriceOracle} from "../contracts/oracle/DIAOracleV2SinglePriceOracle.sol";
import {aspTKNMinimalOracle} from "../contracts/oracle/aspTKNMinimalOracle.sol";
import {IDecentralizedIndex} from "../contracts/interfaces/IDecentralizedIndex.sol";

contract GetAspTknMinimalOraclePrice is Script {
    function run() external view {
        address oracle = vm.envAddress("ORACLE");
        (bool isBadData, uint256 priceLow, uint256 priceHigh) = aspTKNMinimalOracle(oracle).getPrices();

        console.log("isBadData", isBadData);
        console.log("priceLow", priceLow);
        console.log("priceHigh", priceHigh);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/oracle/ChainlinkSinglePriceOracle.sol";
import "../contracts/oracle/UniswapV3SinglePriceOracle.sol";
import {DIAOracleV2SinglePriceOracle} from "../contracts/oracle/DIAOracleV2SinglePriceOracle.sol";
import "../contracts/oracle/V2ReservesUniswap.sol";

contract DeployAllSinglePriceOracles is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address clSequencerFeed = vm.envAddress("SEQUENCER");

        V2ReservesUniswap _v2Res = new V2ReservesUniswap();
        ChainlinkSinglePriceOracle _clOracle = new ChainlinkSinglePriceOracle(clSequencerFeed);
        UniswapV3SinglePriceOracle _uniOracle = new UniswapV3SinglePriceOracle(clSequencerFeed);
        DIAOracleV2SinglePriceOracle _diaOracle = new DIAOracleV2SinglePriceOracle(clSequencerFeed);

        vm.stopBroadcast();

        console.log("V2Reserves deployed to:", address(_v2Res));
        console.log("ChainlinkSinglePriceOracle deployed to:", address(_clOracle));
        console.log("UniswapV3SinglePriceOracle deployed to:", address(_uniOracle));
        console.log("DIAOracleV2SinglePriceOracle deployed to:", address(_diaOracle));
    }
}

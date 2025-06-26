// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/oracle/ChainlinkSinglePriceOracle.sol";
import "../contracts/oracle/UniswapV3SinglePriceOracle.sol";
import "../contracts/oracle/V2ReservesUniswap.sol";
import {DIAOracleV2SinglePriceOracle} from "../contracts/oracle/DIAOracleV2SinglePriceOracle.sol";
import {aspTKNMinimalOracle} from "../contracts/oracle/aspTKNMinimalOracle.sol";
import {IDecentralizedIndex} from "../contracts/interfaces/IDecentralizedIndex.sol";

contract DeployAspTknMinimalOracle is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address aspTkn = vm.envAddress("ASP");
        address base = vm.envAddress("BASE");
        address pod = vm.envAddress("POD");
        address mainClPool = vm.envAddress("POOL");

        V2ReservesUniswap _v2Res = new V2ReservesUniswap();
        ChainlinkSinglePriceOracle _clOracle = new ChainlinkSinglePriceOracle(address(0));
        UniswapV3SinglePriceOracle _uniOracle = new UniswapV3SinglePriceOracle(address(0));
        DIAOracleV2SinglePriceOracle _diaOracle = new DIAOracleV2SinglePriceOracle(address(0));

        aspTKNMinimalOracle _oracle = new aspTKNMinimalOracle(
            aspTkn,
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                base,
                false,
                false,
                IDecentralizedIndex(pod).lpStakingPool(),
                mainClPool
            ),
            abi.encode(address(0), address(0), address(0), address(0), address(0), address(_v2Res))
        );

        vm.stopBroadcast();

        console.log("V2Reserves deployed to:", address(_v2Res));
        console.log("ChainlinkSinglePriceOracle deployed to:", address(_clOracle));
        console.log("UniswapV3SinglePriceOracle deployed to:", address(_uniOracle));
        console.log("DIAOracleV2SinglePriceOracle deployed to:", address(_diaOracle));
        console.log("aspTKNMinimalOracle deployed to:", address(_oracle));
    }
}

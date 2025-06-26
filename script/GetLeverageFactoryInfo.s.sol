// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/lvf/LeverageFactory.sol";

contract GetLeverageFactoryInfo is Script {
    function run() external view {
        address _factory = vm.envAddress("LVF_FACTORY");

        console.log("indexUtils", LeverageFactory(_factory).indexUtils());
        console.log("dexAdapter", LeverageFactory(_factory).dexAdapter());
        console.log("indexManager", LeverageFactory(_factory).indexManager());
        console.log("leverageManager", LeverageFactory(_factory).leverageManager());
        console.log("aspTknFactory", LeverageFactory(_factory).aspTknFactory());
        console.log("aspTknOracleFactory", LeverageFactory(_factory).aspTknOracleFactory());
        console.log("fraxlendPairFactory", LeverageFactory(_factory).fraxlendPairFactory());
        console.log("aspOwnershipTransfer", LeverageFactory(_factory).aspOwnershipTransfer());
    }
}

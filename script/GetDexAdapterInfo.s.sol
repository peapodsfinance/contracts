// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../contracts/interfaces/IDexAdapter.sol";

contract GetDexAdapterInfo is Script {
    function run() external view {
        address _adapter = vm.envAddress("ADAPTER");

        console.log("WETH", IDexAdapter(_adapter).WETH());
        console.log("V2 Router", IDexAdapter(_adapter).V2_ROUTER());
        console.log("V3 Router", IDexAdapter(_adapter).V3_ROUTER());
    }
}

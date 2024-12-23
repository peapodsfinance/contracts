// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../contracts/AutoCompoundingPodLp.sol";

contract SetLpSlippageForAspTkn is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address asp = vm.envAddress("ASP");
        uint256 slippage = vm.envUint("SLIP");

        AutoCompoundingPodLp(asp).setLpSlippage(slippage);

        vm.stopBroadcast();

        console.log("Set LP slippage for aspTKN:", slippage);
    }
}

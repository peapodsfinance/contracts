// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/flash/BalancerFlashSource.sol";
import "../contracts/lvf/LeverageManager.sol";

contract DeployFlashSources is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address lvf = vm.envAddress("LVF");

        address balancer = address(new BalancerFlashSource(lvf));
        LeverageManager(payable(lvf)).setFlashSource(vm.envAddress("ASSET1"), balancer);
        LeverageManager(payable(lvf)).setFlashSource(vm.envAddress("ASSET2"), balancer);

        vm.stopBroadcast();

        console.log("BalancerFlashSource deployed to:", balancer);
    }
}

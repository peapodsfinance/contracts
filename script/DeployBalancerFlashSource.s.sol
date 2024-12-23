// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/flash/BalancerFlashSource.sol";

contract DeployBalancerFlashSource is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address lvf = vm.envAddress("LVF");

        address flashSource = address(new BalancerFlashSource(lvf));

        vm.stopBroadcast();

        console.log("BalancerFlashSource deployed to:", flashSource);
    }
}

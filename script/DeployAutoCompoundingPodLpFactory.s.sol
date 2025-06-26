// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {AutoCompoundingPodLpFactory} from "../contracts/AutoCompoundingPodLpFactory.sol";

contract DeployCore is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        AutoCompoundingPodLpFactory aspFactory = new AutoCompoundingPodLpFactory();

        vm.stopBroadcast();

        console.log("AutoCompoundingPodLpFactory deployed to:", address(aspFactory));
    }
}

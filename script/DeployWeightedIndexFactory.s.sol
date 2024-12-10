// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/WeightedIndexFactory.sol";

contract DeployWeightedIndexFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        WeightedIndexFactory factory = new WeightedIndexFactory();
        factory.setImplementationsAndBeacons(
            vm.envAddress("POD_IMPL"),
            vm.envAddress("SP_IMPL"),
            vm.envAddress("REWARDS_IMPL"),
            vm.envAddress("POD_BEACON"),
            vm.envAddress("SP_BEACON"),
            vm.envAddress("REWARDS_BEACON")
        );

        vm.stopBroadcast();

        // Log the deployed address
        console.log("WeightedIndexFactory deployed to:", address(factory));
    }
}

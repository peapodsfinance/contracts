// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {RewardsWhitelist} from "../contracts/RewardsWhitelist.sol";

contract DeployRewardsWhitelist is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        RewardsWhitelist _w = new RewardsWhitelist();

        vm.stopBroadcast();

        console.log("RewardsWhitelist deployed to:", address(_w));
    }
}

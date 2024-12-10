// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/proxy/LockableUpgradeableBeacon.sol";
import "../contracts/TokenRewards.sol";

contract DeployTokenRewardsBeacon is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        TokenRewards implementation = new TokenRewards();
        console.log("TokenRewards Implementation deployed at:", address(implementation));

        // Deploy beacon
        LockableUpgradeableBeacon beacon =
            new LockableUpgradeableBeacon(address(implementation), vm.addr(deployerPrivateKey));
        console.log("TokenRewards Beacon deployed at:", address(beacon));

        vm.stopBroadcast();
    }
}

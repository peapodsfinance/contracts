// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/proxy/LockableUpgradeableBeacon.sol";
import "../contracts/StakingPoolToken.sol";

contract DeployStakingPoolTokenBeacon is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        StakingPoolToken implementation = new StakingPoolToken();
        console.log("StakingPoolToken Implementation deployed at:", address(implementation));

        // Deploy beacon
        LockableUpgradeableBeacon beacon =
            new LockableUpgradeableBeacon(address(implementation), vm.addr(deployerPrivateKey));
        console.log("StakingPoolToken Beacon deployed at:", address(beacon));

        vm.stopBroadcast();
    }
}

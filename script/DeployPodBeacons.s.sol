// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../contracts/StakingPoolToken.sol";
import "../contracts/TokenRewards.sol";
import "../contracts/WeightedIndex.sol";

contract DeployPodBeacons is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        WeightedIndex podImpl = new WeightedIndex();
        console.log("WeightedIndex Implementation deployed at:", address(podImpl));

        // Deploy beacon
        UpgradeableBeacon podBeacon = new UpgradeableBeacon(address(podImpl), vm.addr(deployerPrivateKey));
        console.log("WeightedIndex Beacon deployed at:", address(podBeacon));

        // Deploy implementation
        StakingPoolToken spImpl = new StakingPoolToken();
        console.log("StakingPoolToken Implementation deployed at:", address(spImpl));

        // Deploy beacon
        UpgradeableBeacon spBeacon = new UpgradeableBeacon(address(spImpl), vm.addr(deployerPrivateKey));
        console.log("StakingPoolToken Beacon deployed at:", address(spBeacon));

        // Deploy implementation
        TokenRewards rewardsImpl = new TokenRewards();
        console.log("TokenRewards Implementation deployed at:", address(rewardsImpl));

        // Deploy beacon
        UpgradeableBeacon rewardsBeacon = new UpgradeableBeacon(address(rewardsImpl), vm.addr(deployerPrivateKey));
        console.log("TokenRewards Beacon deployed at:", address(rewardsBeacon));

        vm.stopBroadcast();
    }
}

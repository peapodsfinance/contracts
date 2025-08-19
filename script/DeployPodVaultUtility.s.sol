// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/PodVaultUtility.sol";

contract DeployPodVaultUtility is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the PodVaultUtility contract
        PodVaultUtility utility = new PodVaultUtility();

        console.log("PodVaultUtility deployed at:", address(utility));

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/PEAS.sol";

contract DeployPEAS is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy PEAS token
        PEAS peas = new PEAS("Peapods Finance", "PEAS");

        vm.stopBroadcast();

        // Log the deployed address
        console.log("PEAS token deployed to:", address(peas));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../test/mocks/TestERC20.sol";

contract DeployTestERC20 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TestERC20 token = new TestERC20(vm.envString("NAME"), vm.envString("SYMBOL"));

        vm.stopBroadcast();

        // Log the deployed address
        console.log("Token deployed to:", address(token));
    }
}

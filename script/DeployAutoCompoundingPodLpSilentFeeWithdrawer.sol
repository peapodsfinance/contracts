// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {AutoCompoundingPodLpSilentFeeWithdrawer} from "../contracts/AutoCompoundingPodLpSilentFeeWithdrawer.sol";

contract DeployAutoCompoundingPodLpSilentFeeWithdrawer is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        AutoCompoundingPodLpSilentFeeWithdrawer _withdrawer = new AutoCompoundingPodLpSilentFeeWithdrawer();
        console.log("Deployed withdrawer to:", address(_withdrawer));

        vm.stopBroadcast();

        console.log("Success!");
    }
}

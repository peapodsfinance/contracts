// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/RewardsWhitelist.sol";

contract WhitelistFromDebondFee is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        address _whitelister = vm.envAddress("WHITELISTER");
        address _contract = vm.envAddress("CA");

        RewardsWhitelist(_whitelister).setWhitelistFromDebondFees(_contract, true);

        vm.stopBroadcast();

        console.log("Success!");
    }
}

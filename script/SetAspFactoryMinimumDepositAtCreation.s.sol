// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/AutoCompoundingPodLpFactory.sol";
import "../contracts/lvf/LeverageFactory.sol";

contract SetAspFactoryMinimumDepositAtCreation is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        LeverageFactory(vm.envAddress("LEV_FACTORY"))
            .transferContractOwnership(vm.envAddress("ASP_FACTORY"), vm.addr(vm.envUint("PRIVATE_KEY")));
        AutoCompoundingPodLpFactory(vm.envAddress("ASP_FACTORY")).setMinimumDepositAtCreation(0);
        AutoCompoundingPodLpFactory(vm.envAddress("ASP_FACTORY")).transferOwnership(vm.envAddress("LEV_FACTORY"));

        vm.stopBroadcast();

        console.log("Success!");
    }
}

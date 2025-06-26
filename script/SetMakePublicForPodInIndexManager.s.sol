// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/IndexManager.sol";

contract SetMakePublicForPodInIndexManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address idxMgr = vm.envAddress("INDEX_MANAGER");

        IndexManager(idxMgr).updateMakePublic(vm.envAddress("POD"), true);

        vm.stopBroadcast();

        console.log("Success!");
    }
}

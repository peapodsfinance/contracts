// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {IWeightedIndexFactory} from "../contracts/interfaces/IWeightedIndexFactory.sol";
import {IndexManager} from "../contracts/IndexManager.sol";

contract DeployIndexManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        IWeightedIndexFactory podFactory = IWeightedIndexFactory(vm.envAddress("POD_FACTORY"));
        IndexManager indexManager = new IndexManager(podFactory);

        vm.stopBroadcast();

        console.log("IndexManager deployed to:", address(indexManager));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../contracts/lvf/LeverageFactory.sol";

contract SetLeverageFactoryDependencies is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        LeverageFactory(vm.envAddress("LEV_FACTORY")).setLevMgrAndFactories(
            address(0), address(0), vm.envAddress("INDEX_MANAGER"), address(0), address(0), address(0), address(0)
        );

        vm.stopBroadcast();

        console.log("Success!");
    }
}

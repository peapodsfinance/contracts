// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {aspTKNMinimalOracleFactory} from "../contracts/oracle/aspTKNMinimalOracleFactory.sol";
import {LeverageFactory} from "../contracts/lvf/LeverageFactory.sol";

contract DeployAspTKNMinimalOracleFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        aspTKNMinimalOracleFactory aspOracleFactory = new aspTKNMinimalOracleFactory();
        Ownable(address(aspOracleFactory)).transferOwnership(vm.envAddress("LEV_FACTORY"));
        LeverageFactory(vm.envAddress("LEV_FACTORY"))
            .setLevMgrAndFactories(
                address(0), address(0), address(0), address(0), address(0), address(aspOracleFactory), address(0)
            );

        vm.stopBroadcast();

        console.log("aspTKNMinimalOracleFactory deployed to:", address(aspOracleFactory));
    }
}

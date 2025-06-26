// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../contracts/lvf/LeverageFactory.sol";

contract SetOwnablesFromLeverageFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address _levFactory = vm.envAddress("LEV_FACTORY");
        address _owner = vm.envAddress("OWNER");

        LeverageFactory(_levFactory).transferContractOwnership(vm.envAddress("LVF"), _owner);
        LeverageFactory(_levFactory).transferContractOwnership(vm.envAddress("ASP_FACTORY"), _owner);
        LeverageFactory(_levFactory).transferContractOwnership(vm.envAddress("ASP_ORACLE_FACTORY"), _owner);

        vm.stopBroadcast();

        console.log("Success!");
    }
}

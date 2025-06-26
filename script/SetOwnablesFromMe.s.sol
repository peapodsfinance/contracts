// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../contracts/lvf/LeverageFactory.sol";

contract SetOwnablesFromMe is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address _owner = vm.envAddress("OWNER");

        Ownable(vm.envAddress("LVF")).transferOwnership(_owner);
        Ownable(vm.envAddress("ASP_FACTORY")).transferOwnership(_owner);
        Ownable(vm.envAddress("ASP_ORACLE_FACTORY")).transferOwnership(_owner);

        vm.stopBroadcast();

        console.log("Success!");
    }
}

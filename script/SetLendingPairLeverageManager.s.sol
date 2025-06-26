// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../contracts/lvf/LeverageManager.sol";

contract SetLendingPairLeverageManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        LeverageManager(payable(vm.envAddress("LVF"))).setLendingPair(vm.envAddress("POD"), vm.envAddress("PAIR"));

        vm.stopBroadcast();

        console.log("Success!");
    }
}

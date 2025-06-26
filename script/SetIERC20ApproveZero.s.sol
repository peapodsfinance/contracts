// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract SetIERC20ApproveZero is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address token = vm.envAddress("TOKEN");
        address spender = vm.envAddress("SPENDER");
        IERC20(token).approve(spender, 0);

        vm.stopBroadcast();

        console.log("Success!");
    }
}

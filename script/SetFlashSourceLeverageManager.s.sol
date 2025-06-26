// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../contracts/lvf/LeverageManager.sol";

contract SetFlashSourceLeverageManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address lvf = vm.envAddress("LVF");
        address borrowAsset = vm.envAddress("BORROW_ASSET");
        address flashSource = vm.envAddress("FLASH_SOURCE");

        LeverageManager(payable(lvf)).setFlashSource(borrowAsset, flashSource);

        vm.stopBroadcast();

        console.log("Successfully set flash source!");
    }
}

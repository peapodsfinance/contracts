// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/lvf/LeverageManager.sol";

contract DeployLeverageManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        string memory name = vm.envString("NAME");
        string memory symbol = vm.envString("SYMBOL");
        address indexUtils = vm.envAddress("INDEX_UTILS");

        LeverageManager _levManager = new LeverageManager(name, symbol, IIndexUtils(indexUtils));

        vm.stopBroadcast();

        console.log("LeverageManager deployed to:", address(_levManager));
    }
}

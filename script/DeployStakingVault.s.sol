// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/utils/StakingVault.sol";

contract DeployStakingVault is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address asset = vm.envAddress("ASSET");
        string memory name = vm.envString("NAME");
        string memory symbol = vm.envString("SYMBOL");

        StakingVault vault = new StakingVault(IERC20(asset), name, symbol);

        vm.stopBroadcast();

        console.log("StakingVault deployed to:", address(vault));
        console.log("  Asset:", asset);
        console.log("  Name:", name);
        console.log("  Symbol:", symbol);
    }
}

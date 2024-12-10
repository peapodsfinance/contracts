// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../contracts/LendingAssetVault.sol";

contract DeployLendingAssetVault is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address asset = vm.envAddress("ASSET");

        address lav = address(
            new LendingAssetVault(
                string.concat("MetaVault for ", IERC20Metadata(asset).name()),
                string.concat("lav", IERC20Metadata(asset).symbol()),
                asset
            )
        );

        vm.stopBroadcast();

        console.log("LAV deployed to:", address(lav));
    }
}

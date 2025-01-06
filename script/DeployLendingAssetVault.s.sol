// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../contracts/LendingAssetVaultFactory.sol";

contract DeployLendingAssetVault is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address factory = vm.envAddress("LAV_FACTORY");
        address asset = vm.envAddress("ASSET");

        uint256 _depAmount = LendingAssetVaultFactory(factory).minimumDepositAtCreation();
        IERC20(asset).approve(factory, _depAmount);
        address lav = LendingAssetVaultFactory(factory).create(
            string.concat("MetaVault for ", IERC20Metadata(asset).name()),
            string.concat("mv", IERC20Metadata(asset).symbol()),
            asset,
            0
        );

        vm.stopBroadcast();

        console.log("LAV deployed to:", lav);
    }
}

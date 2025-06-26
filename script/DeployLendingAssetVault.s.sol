// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../contracts/LendingAssetVaultFactory.sol";

contract DeployLendingAssetVault is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address factory = vm.envAddress("LAV_FACTORY");
        address asset1 = vm.envAddress("ASSET1");
        address asset2 = vm.envAddress("ASSET2");
        address asset3 = vm.envAddress("ASSET3");

        uint256 _depAmount = LendingAssetVaultFactory(factory).minimumDepositAtCreation();

        // asset1
        IERC20(asset1).approve(factory, _depAmount);
        address lav1 = LendingAssetVaultFactory(factory).create(
            string.concat("Peapods Metavault for ", IERC20Metadata(asset1).name()),
            string.concat("pv", IERC20Metadata(asset1).symbol()),
            asset1,
            0
        );

        // asset2
        IERC20(asset2).approve(factory, _depAmount);
        address lav2 = LendingAssetVaultFactory(factory).create(
            string.concat("Peapods Metavault for ", IERC20Metadata(asset2).name()),
            string.concat("pv", IERC20Metadata(asset2).symbol()),
            asset2,
            0
        );

        // asset3
        IERC20(asset3).approve(factory, _depAmount);
        address lav3 = LendingAssetVaultFactory(factory).create(
            string.concat("Peapods Metavault for ", IERC20Metadata(asset3).name()),
            string.concat("pv", IERC20Metadata(asset3).symbol()),
            asset3,
            0
        );

        vm.stopBroadcast();

        console.log("Metavault (", IERC20Metadata(asset1).symbol(), ") deployed to:", lav1);
        console.log("Metavault (", IERC20Metadata(asset2).symbol(), ") deployed to:", lav2);
        console.log("Metavault (", IERC20Metadata(asset3).symbol(), ") deployed to:", lav3);
    }
}

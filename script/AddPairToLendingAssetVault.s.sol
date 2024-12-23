// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../contracts/LendingAssetVault.sol";

contract AddPairToLendingAssetVault is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // address receiver = vm.addr(deployerPrivateKey);

        address lav = vm.envAddress("LAV");
        address pair = vm.envAddress("PAIR");

        LendingAssetVault(lav).setVaultWhitelist(pair, true);

        address[] memory _vaults = new address[](1);
        _vaults[0] = pair;
        uint256[] memory _allocation = new uint256[](1);
        _allocation[0] = 100e18;
        LendingAssetVault(lav).setVaultMaxAllocation(_vaults, _allocation);

        vm.stopBroadcast();

        console.log("Added pair to LAV:", pair);
    }
}

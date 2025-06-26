// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/LendingAssetVault.sol";

interface IFraxlendPairSetter {
    function setExternalAssetVault(address vault) external;
}

contract SetLendingAssetVaultMaxAllocation is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        address _metavault = vm.envAddress("LAV");

        address[] memory _vaults = new address[](5);
        _vaults[0] = 0xE6824946999f81AFC655C9e78080Af6793E572CD;
        _vaults[1] = 0x1fA06D258CAbA59b1B8d94686873CcE393351e98;
        _vaults[2] = 0x4504597dcdbc5fA42808590D626378c47f046DE5;
        _vaults[3] = 0x6cc696b3f7eDf42D1F51dd99eDa181044Cd25100;
        _vaults[4] = 0xDcC57BD016bEE409A3DA258496184E8107ba8E1e;

        for (uint256 _i; _i < _vaults.length; _i++) {
            LendingAssetVault(_metavault).setVaultWhitelist(_vaults[_i], true);
            IFraxlendPairSetter(_vaults[_i]).setExternalAssetVault(_metavault);
        }

        // uint256[] memory _allocation = new uint256[](3);
        // _allocation[0] = 100000000;
        // _allocation[1] = 100000000;
        // _allocation[2] = 100000000;
        // LendingAssetVault(_metavault).setVaultMaxAllocation(_vaults, _allocation);

        vm.stopBroadcast();

        console.log("Success!");
    }
}

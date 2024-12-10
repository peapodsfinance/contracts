// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../contracts/LendingAssetVault.sol";

contract DepositToLendingAssetVault is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address receiver = vm.addr(deployerPrivateKey);

        address lav = vm.envAddress("LAV");
        uint256 amount = vm.envUint("AMOUNT");
        address asset = LendingAssetVault(lav).asset();

        IERC20(asset).approve(lav, amount);
        uint256 shares = LendingAssetVault(lav).deposit(amount, receiver);

        vm.stopBroadcast();

        console.log("Deposited to LAV and received:", shares);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../contracts/AutoCompoundingPodLp.sol";

contract DepositToAspTkn is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address receiver = vm.addr(deployerPrivateKey);

        address asp = vm.envAddress("ASP");
        uint256 amount = vm.envUint("AMOUNT");
        address asset = AutoCompoundingPodLp(asp).asset();

        IERC20(asset).approve(asp, amount);
        uint256 shares = AutoCompoundingPodLp(asp).deposit(amount, receiver);

        vm.stopBroadcast();

        console.log("Deposited to aspTKN and received:", shares);
    }
}

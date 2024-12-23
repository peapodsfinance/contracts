// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../contracts/AutoCompoundingPodLp.sol";

contract WithdrawFromAspTkn is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address receiver = vm.addr(deployerPrivateKey);

        address asp = vm.envAddress("ASP");
        uint256 shares = vm.envUint("SHARES");

        uint256 amount = AutoCompoundingPodLp(asp).redeem(shares, receiver, receiver);

        vm.stopBroadcast();

        console.log("Redeemed from aspTKN and received:", amount);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

contract EmptyTransactions is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address _deployer = vm.addr(deployerPrivateKey);

        uint256 _num = vm.envUint("NUM");

        for (uint256 _i; _i < _num; _i++) {
            (bool _s,) = payable(_deployer).call{value: 0}("");
            require(_s);
        }

        vm.stopBroadcast();

        console.log("Executed empty transactions:", _num);
    }
}

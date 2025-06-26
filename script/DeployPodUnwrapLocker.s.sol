// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/PodUnwrapLocker.sol";

contract DeployPodUnwrapLocker is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address protocolOwnable = vm.envAddress("PROTOCOL_OWNABLE");
        vm.startBroadcast(deployerPrivateKey);

        PodUnwrapLocker locker = new PodUnwrapLocker(protocolOwnable);

        console.log("PodUnwrapLocker deployed to:", address(locker));

        vm.stopBroadcast();
    }
}

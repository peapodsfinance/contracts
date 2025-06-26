// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/LendingAssetVault.sol";

interface IOFT {
    function setPeer(uint32 _eid, bytes32 _peer) external;
}

contract SetOFTPeer is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        address _oft = vm.envAddress("OFT");
        uint256 _eid = vm.envUint("EID");
        address _peer = vm.envAddress("PEER");

        IOFT(_oft).setPeer(uint32(_eid), bytes32(uint256(uint160(_peer))));

        vm.stopBroadcast();

        console.log("Success!");
    }
}

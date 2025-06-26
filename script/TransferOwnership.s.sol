// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TransferOwnership is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address _owner = vm.envAddress("OWNER");
        Ownable(vm.envAddress("CA")).transferOwnership(_owner);

        vm.stopBroadcast();

        console.log("Successfully transferred ownership tp!", _owner);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/flash/MoolahFlashSource.sol";
import "../contracts/lvf/LeverageFactory.sol";
import "../contracts/lvf/LeverageManager.sol";

contract DeployFlashSources is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address lvf = 0x7189B95CaCCC2E5734b1592CCC8CaeAeb87573f5;
        address levFact = 0xDea69B4ac0fB33b472E389f49F2876b98075E918;

        LeverageFactory(levFact).transferContractOwnership(lvf, vm.addr(vm.envUint("PRIVATE_KEY")));
        address balancer = address(new MoolahFlashSource(lvf, 0x8F73b65B4caAf64FBA2aF91cC5D4a2A1318E5D8C));
        LeverageManager(payable(lvf)).setFlashSource(0x55d398326f99059fF775485246999027B3197955, balancer);
        LeverageManager(payable(lvf)).setFlashSource(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c, balancer);
        LeverageManager(payable(lvf)).transferOwnership(levFact);

        vm.stopBroadcast();

        console.log("MoolahFlashSource deployed to:", balancer);
    }
}

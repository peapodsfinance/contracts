// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../contracts/lvf/LeverageFactory.sol";

contract DeployLeverageFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address _currentFactory = vm.envAddress("FACTORY");

        LeverageFactory _levFactory = new LeverageFactory(
            vm.envAddress("INDEX_UTILS"),
            vm.envAddress("DEX_ADAPTER"),
            vm.envAddress("INDEX_MANAGER"),
            vm.envAddress("LVF"),
            vm.envAddress("ASP_FACTORY"),
            vm.envAddress("ASP_ORACLE_FACTORY"),
            vm.envAddress("FRAX_DEPLOYER"),
            vm.envAddress("ASP_OWNER")
        );

        // Ownable(vm.envAddress("LVF")).transferOwnership(address(_levFactory));
        // Ownable(vm.envAddress("ASP_FACTORY")).transferOwnership(address(_levFactory));
        // Ownable(vm.envAddress("ASP_ORACLE_FACTORY")).transferOwnership(address(_levFactory));
        LeverageFactory(_currentFactory).transferContractOwnership(vm.envAddress("LVF"), address(_levFactory));
        LeverageFactory(_currentFactory).transferContractOwnership(vm.envAddress("ASP_FACTORY"), address(_levFactory));
        LeverageFactory(_currentFactory)
            .transferContractOwnership(vm.envAddress("ASP_ORACLE_FACTORY"), address(_levFactory));

        vm.stopBroadcast();

        console.log("LeverageFactory deployed to:", address(_levFactory));
    }
}

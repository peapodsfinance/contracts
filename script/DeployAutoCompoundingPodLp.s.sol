// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../contracts/interfaces/IDecentralizedIndex.sol";
import "../contracts/interfaces/IDexAdapter.sol";
import "../contracts/interfaces/IIndexUtils.sol";
import "../contracts/AutoCompoundingPodLpFactory.sol";

contract DeployAutoCompoundingPodLp is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address aspFactory = vm.envAddress("ASP_FACTORY");
        address pod = vm.envAddress("POD");
        address dexAdapter = vm.envAddress("ADAPTER");
        address indexUtils = vm.envAddress("UTILS");

        uint256 _depAmount = AutoCompoundingPodLpFactory(aspFactory).minimumDepositAtCreation();
        IERC20(IDecentralizedIndex(pod).lpStakingPool()).approve(aspFactory, _depAmount);
        address asp = AutoCompoundingPodLpFactory(aspFactory).create(
            string.concat("Auto Compounding LP for ", IERC20Metadata(pod).name()),
            string.concat("as", IERC20Metadata(pod).symbol()),
            false,
            IDecentralizedIndex(pod),
            IDexAdapter(dexAdapter),
            IIndexUtils(indexUtils),
            0
        );

        vm.stopBroadcast();

        console.log("aspTKN deployed to:", asp);
    }
}

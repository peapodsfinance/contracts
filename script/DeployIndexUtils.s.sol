// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/IndexUtils.sol";
import "../contracts/interfaces/IDexAdapter.sol";
import "../contracts/interfaces/IV3TwapUtilities.sol";
import "../contracts/dex/UniswapDexAdapter.sol";

contract DeployIndexUtils is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address twapUtils = vm.envAddress("TWAP_UTILS");
        address adapter = vm.envAddress("ADAPTER");

        IndexUtils _indexUtils = new IndexUtils(IV3TwapUtilities(twapUtils), IDexAdapter(adapter));

        vm.stopBroadcast();

        console.log("IndexUtils deployed to:", address(_indexUtils));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/IndexUtils.sol";
import "../contracts/interfaces/IV3TwapUtilities.sol";
import "../contracts/dex/UniswapDexAdapter.sol";

contract DeployUniswapDexAdapter is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address twapUtils = vm.envAddress("UTILS");
        address v2Router = vm.envAddress("V2");
        address v3Router = vm.envAddress("V3");
        bool asyncLoad = vm.envUint("ASYNC") == 1;

        UniswapDexAdapter _adapter = new UniswapDexAdapter(IV3TwapUtilities(twapUtils), v2Router, v3Router, asyncLoad);

        IndexUtils _indexUtils = new IndexUtils(IV3TwapUtilities(twapUtils), _adapter);

        vm.stopBroadcast();

        console.log("Dex adapter deployed to:", address(_adapter));
        console.log("IndexUtils deployed to:", address(_indexUtils));
    }
}

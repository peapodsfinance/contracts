// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/interfaces/IIndexManager.sol";
import "../contracts/WeightedIndex.sol";

contract DeployVerificationPod is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        IDecentralizedIndex.Config memory _c;
        address[] memory _t = new address[](1);
        _t[0] = 0x02f92800F57BCD74066F5709F1Daa1A4302Df875;
        uint256[] memory _w = new uint256[](1);
        _w[0] = 1e18;
        address _pod = IIndexManager(vm.envAddress("INDEX_MANAGER")).deployNewIndex(
            "Verification",
            "pVER",
            abi.encode(_c, _getFees(), _t, _w, address(0), false),
            _getImmutables(
                vm.envAddress("DAI"),
                vm.envAddress("FEE_ROUTER"),
                vm.envAddress("REWARDS"),
                vm.envAddress("TWAP_UTILS"),
                vm.envAddress("ADAPTER")
            )
        );

        vm.stopBroadcast();

        console.log("Pod deployed to:", _pod);
    }

    function _getFees() internal pure returns (IDecentralizedIndex.Fees memory) {
        return IDecentralizedIndex.Fees({
            burn: uint16(2000),
            bond: uint16(100),
            debond: uint16(100),
            buy: uint16(50),
            sell: uint16(50),
            partner: uint16(0)
        });
    }

    function _getImmutables(
        address dai,
        address feeRouter,
        address rewardsWhitelist,
        address twapUtils,
        address dexAdapter
    ) internal pure returns (bytes memory) {
        return abi.encode(
            dai, 0x02f92800F57BCD74066F5709F1Daa1A4302Df875, dai, feeRouter, rewardsWhitelist, twapUtils, dexAdapter
        );
    }
}

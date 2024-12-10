// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/IndexManager.sol";
import "../contracts/ProtocolFees.sol";
import "../contracts/ProtocolFeeRouter.sol";
import "../contracts/RewardsWhitelist.sol";
import "../contracts/WeightedIndexFactory.sol";
import "../contracts/twaputils/V3TwapCamelotUtilities.sol";
import "../contracts/twaputils/V3TwapKimUtilities.sol";
import "../contracts/twaputils/V3TwapUtilities.sol";

contract DeployCore is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 twapUtilsType = vm.envUint("TWAP_TYPE");
        vm.startBroadcast(deployerPrivateKey);

        WeightedIndexFactory podDeployer = new WeightedIndexFactory();
        IndexManager indexManager = new IndexManager(podDeployer);
        ProtocolFees protocolFees = new ProtocolFees();
        ProtocolFeeRouter protocolFeeRouter = new ProtocolFeeRouter(protocolFees);
        RewardsWhitelist rewardsWhitelist = new RewardsWhitelist();

        // Deploy V3TwapUtilities
        address v3TwapUtils;
        if (twapUtilsType == 1) {
            v3TwapUtils = address(new V3TwapCamelotUtilities());
        } else if (twapUtilsType == 2) {
            v3TwapUtils = address(new V3TwapKimUtilities());
        } else {
            v3TwapUtils = address(new V3TwapUtilities());
        }

        vm.stopBroadcast();

        // Log the deployed addresses
        console.log("IndexManager deployed to:", address(indexManager));
        console.log("ProtocolFees deployed to:", address(protocolFees));
        console.log("ProtocolFeeRouter deployed to:", address(protocolFeeRouter));
        console.log("RewardsWhitelist deployed to:", address(rewardsWhitelist));
        console.log("V3TwapUtilities deployed to:", v3TwapUtils);
    }
}

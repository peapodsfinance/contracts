// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {aspTKNMinimalOracleFactory} from "../contracts/oracle/aspTKNMinimalOracleFactory.sol";
import {AutoCompoundingPodLpFactory} from "../contracts/AutoCompoundingPodLpFactory.sol";
import {IndexManager} from "../contracts/IndexManager.sol";
import {LendingAssetVaultFactory} from "../contracts/LendingAssetVaultFactory.sol";
import {ProtocolFees} from "../contracts/ProtocolFees.sol";
import {ProtocolFeeRouter} from "../contracts/ProtocolFeeRouter.sol";
import {RewardsWhitelist} from "../contracts/RewardsWhitelist.sol";
import {WeightedIndexFactory} from "../contracts/WeightedIndexFactory.sol";
import {V3TwapCamelotUtilities} from "../contracts/twaputils/V3TwapCamelotUtilities.sol";
import {V3TwapKimUtilities} from "../contracts/twaputils/V3TwapKimUtilities.sol";
import {V3TwapKodiakUtilities} from "../contracts/twaputils/V3TwapKodiakUtilities.sol";
import {V3TwapShadowUtilities} from "../contracts/twaputils/V3TwapShadowUtilities.sol";
import {V3TwapUtilities} from "../contracts/twaputils/V3TwapUtilities.sol";

contract DeployCore is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 twapUtilsType = vm.envUint("TWAP_TYPE");
        vm.startBroadcast(deployerPrivateKey);

        aspTKNMinimalOracleFactory aspOracleFactory = new aspTKNMinimalOracleFactory();
        AutoCompoundingPodLpFactory aspFactory = new AutoCompoundingPodLpFactory();
        LendingAssetVaultFactory lavFactory = new LendingAssetVaultFactory();
        WeightedIndexFactory podFactory = new WeightedIndexFactory();

        try vm.envAddress("POD_IMPL") returns (address _podImpl) {
            podFactory.setImplementationsAndBeacons(
                _podImpl,
                vm.envAddress("SP_IMPL"),
                vm.envAddress("REWARDS_IMPL"),
                vm.envAddress("POD_BEACON"),
                vm.envAddress("SP_BEACON"),
                vm.envAddress("REWARDS_BEACON")
            );
        } catch {
            console.log("No implementations/beacons to set in podFactory...");
        }

        IndexManager indexManager = new IndexManager(podFactory);
        ProtocolFees protocolFees = new ProtocolFees();
        ProtocolFeeRouter protocolFeeRouter = new ProtocolFeeRouter(protocolFees);
        RewardsWhitelist rewardsWhitelist = new RewardsWhitelist();

        // Deploy V3TwapUtilities
        address v3TwapUtils;
        if (twapUtilsType == 1) {
            v3TwapUtils = address(new V3TwapCamelotUtilities());
        } else if (twapUtilsType == 2) {
            v3TwapUtils = address(new V3TwapKimUtilities());
        } else if (twapUtilsType == 3) {
            v3TwapUtils = address(new V3TwapShadowUtilities());
        } else if (twapUtilsType == 4) {
            v3TwapUtils = address(new V3TwapKodiakUtilities());
        } else {
            v3TwapUtils = address(new V3TwapUtilities());
        }

        vm.stopBroadcast();

        // Log the deployed addresses
        console.log("aspTKNMinimalOracleFactory deployed to:", address(aspOracleFactory));
        console.log("AutoCompoundingPodLpFactory deployed to:", address(aspFactory));
        console.log("LendingAssetVaultFactory deployed to:", address(lavFactory));
        console.log("WeightedIndexFactory deployed to:", address(podFactory));
        console.log("IndexManager deployed to:", address(indexManager));
        console.log("ProtocolFees deployed to:", address(protocolFees));
        console.log("ProtocolFeeRouter deployed to:", address(protocolFeeRouter));
        console.log("RewardsWhitelist deployed to:", address(rewardsWhitelist));
        console.log("V3TwapUtilities deployed to:", v3TwapUtils);
    }
}

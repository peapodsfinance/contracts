// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {PodHandler} from "../handlers/PodHandler.sol";
import {LeverageManagerHandler} from "../handlers/LeverageManagerHandler.sol";
import {AutoCompoundingPodLpHandler} from "../handlers/AutoCompoundingPodLpHandler.sol";
import {StakingPoolHandler} from "../handlers/StakingPoolHandler.sol";
import {LendingAssetVaultHandler} from "../handlers/LendingAssetVaultHandler.sol";
import {FraxlendPairHandler} from "../handlers/FraxlendPairHandler.sol";

contract ForgeTest is 
PodHandler,
LeverageManagerHandler,
AutoCompoundingPodLpHandler,
StakingPoolHandler,
LendingAssetVaultHandler,
FraxlendPairHandler
 {

    function setUp() public {
        setup();
    }

    function test_replay() public {
        lendingAssetVault_donate(0,3);
        lendingAssetVault_mint(0,0,2);
}
}
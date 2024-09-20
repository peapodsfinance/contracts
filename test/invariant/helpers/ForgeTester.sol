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

    function test_dev() public {
        fraxPair_deposit(0,2,28858282016474148323380138389644183560448134250821003014286330,19658559300323799291525953680803162987235102486231753707384080);
        fraxPair_redeem(8544901073676212775336981473833990393453222625327784000168884360415741344,5584320228510000432910404583545564968989443605617730561042188509,0,1);
    }
}
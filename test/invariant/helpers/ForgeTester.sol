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
    try this.lendingAssetVault_donate(736691403230857269277838203195694890813718439145607117493747042817778110,17081964326684106198295361262369301430368491906304570636014621327258848) {} catch {}

    try this.lendingAssetVault_deposit(2117,129252049,2219754581402872459996666608925023612649750700295324106471858206027448548144) {} catch {}

    try this.lendingAssetVault_withdraw(3215533668980591452335531284937387630928379289574405735645132938955493834590,21,736528841229307456185314663296160965387281734200251877348810432918308067104) {} catch {}

    invariant_POD_23();

}
}
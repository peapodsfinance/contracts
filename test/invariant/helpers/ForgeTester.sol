// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {PodHandler} from "../handlers/PodHandler.sol";
import {LeverageManagerHandler} from "../handlers/LeverageManagerHandler.sol";

contract ForgeTest is 
PodHandler,
LeverageManagerHandler
 {

    function setUp() public {
        setup();
    }

    function test_dev() public {
        pod_bond(58674322, 132456758, 675342, 10e6);
    }

function test_replay() public {
    try this.pod_bond(60368996004287070098368459248557667205656112432905753783,0,4301786472253652845350072542570002717,2957770918367260649) {} catch {}

    try this.leverageManager_initializePosition(0,0) {} catch {}

    try this.leverageManager_addLeverage(75314134675099191216470435,100490455530872,0) {} catch {}

    leverageManager_removeLeverage(1076434720400324068359374440509565996624826229222693,1,1);

}
}
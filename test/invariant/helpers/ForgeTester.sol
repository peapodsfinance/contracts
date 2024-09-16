// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {PodHandler} from "../handlers/PodHandler.sol";
import {LeverageManagerHandler} from "../handlers/LeverageManagerHandler.sol";
import {AutoCompoundingPodLpHandler} from "../handlers/AutoCompoundingPodLpHandler.sol";
import {StakingPoolHandler} from "../handlers/StakingPoolHandler.sol";

contract ForgeTest is 
PodHandler,
LeverageManagerHandler,
AutoCompoundingPodLpHandler,
StakingPoolHandler
 {

    function setUp() public {
        setup();
    }

    function test_dev() public {
        pod_bond(58674322, 132456758, 675342, 10e6);
    }

function test_replay() public {
    try this.leverageManager_initializePosition(0,0) {} catch {}

    try this.pod_bond(20180120539695251556645604394296167437509287624699431846322917558764461,2444,97574173774269861519495942689171021322556056119902607577527,117141720952656) {} catch {}

    try this.leverageManager_addLeverage(62148433841201948443254638161347911850160712710704543,794681649878405447865254547203594707985212448560966,38273503283474111381833762314382033367152007) {} catch {}

    vm.warp(block.timestamp + 1);
    vm.roll(block.number + 1);
    leverageManager_removeLeverage(571459865496049496880799,819299572132,1631174878);

}
}
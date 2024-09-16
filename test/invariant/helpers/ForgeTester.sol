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
    try this.pod_bond(191981292330884613804461926233350489297622813803764996016997095005771,23351849,266849604775266255171506184813966608070365569425153501338506158923,310526165347251236191894375515114985986680312757760021198066711865657) {} catch {}

    try this.leverageManager_initializePosition(1,1) {} catch {}

    try this.leverageManager_addLeverage(193284649226357054756419461260662201315,166907119036401435728503092740712470243063005101287,164251919931567300823525) {} catch {}

    try this.pod_addLiquidityV2(2645085155109137633356641879093391926015649908401637243370281344674635085,145213,156977934,501291097760628477702704715199246910489902041015468345923110552405015681) {} catch {}

    try this.stakingPool_stake(21302023051708918390342302320583766413404196547810090169056199918859071467,9,232028823214838997116871130927731704501432744396969301711631508408331873) {} catch {}

    vm.warp(block.timestamp + 23);
    vm.roll(block.number + 1);

    aspTKN_mint(57752347941326587647353508072646067322161231848955642667694874388822083527,0,1,8);

}
}
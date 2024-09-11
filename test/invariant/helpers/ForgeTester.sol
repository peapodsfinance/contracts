// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {PodHandler} from "../handlers/PodHandler.sol";

contract ForgeTest is PodHandler {

    function setUp() public {
        setup();
    }

    function test_dev() public {
        pod_bond(58674322, 132456758, 675342, 10e6);
    }

    function test_replay() public {
    try this.pod_bond(48382842615255689847034501202756352529392189104,3399834414902803432814409327056580511953071028588061,8361270076545964082752765582627155,3944258853802684539685486) {} catch {}

    pod_debond(6672815514642684294886297346912059024577,2726553818268443701908143807032106988348364,326137471604557270);

}
}
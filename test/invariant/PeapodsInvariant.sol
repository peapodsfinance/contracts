// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {PodHandler} from "./handlers/PodHandler.sol";
import {LeverageManagerHandler} from "./handlers/LeverageManagerHandler.sol";
import {AutoCompoundingPodLpHandler} from "./handlers/AutoCompoundingPodLpHandler.sol";
import {StakingPoolHandler} from "./handlers/StakingPoolHandler.sol";

contract PeapodsInvariant is 
PodHandler,
LeverageManagerHandler,
AutoCompoundingPodLpHandler,
StakingPoolHandler
 {
    constructor() payable {
        setup();
    }
}
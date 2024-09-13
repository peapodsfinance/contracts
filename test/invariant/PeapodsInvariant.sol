// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {PodHandler} from "./handlers/PodHandler.sol";
import {LeverageManagerHandler} from "./handlers/LeverageManagerHandler.sol";

contract PeapodsInvariant is 
PodHandler,
LeverageManagerHandler
 {
    constructor() payable {
        setup();
    }
}
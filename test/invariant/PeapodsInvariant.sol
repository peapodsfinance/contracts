// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {PodHandler} from "./handlers/PodHandler.sol";

contract PeapodsInvariant is PodHandler {
    constructor() payable {
        setup();
    }
}
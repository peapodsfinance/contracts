// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Handler} from "./handlers/Handler.sol";

contract PeapodsInvariant is Handler {
    constructor() payable {
        setup();
    }
}
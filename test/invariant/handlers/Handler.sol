// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Properties} from "../helpers/Properties.sol";

contract Handler is Properties {

    function Handler_Test() public {
        fl.t(false, "TEST");
    }
}
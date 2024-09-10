// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Handler} from "../handlers/Handler.sol";

contract ForgeTest is Handler {

    function setUp() public {
        setup();
    }

    function test_dev() public {
        fl.t(false, "SETUP");
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test, console2 } from 'forge-std/Test.sol';
import '../contracts/PEAS.sol';

contract CounterTest is Test {
  PEAS public peas;

  function setUp() public {
    peas = new PEAS('Peapods', 'PEAS');
  }

  function test_balanceOf() public {
    assertEq(peas.balanceOf(address(this)), peas.totalSupply());
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test, console2 } from 'forge-std/Test.sol';
import { PEAS } from '../contracts/PEAS.sol';
import { V3TwapUtilities } from '../contracts/twaputils/V3TwapUtilities.sol';
import { UniswapDexAdapter } from '../contracts/dex/UniswapDexAdapter.sol';
import { IDecentralizedIndex } from '../contracts/interfaces/IDecentralizedIndex.sol';
import { WeightedIndex } from '../contracts/WeightedIndex.sol';

contract WeightedIndexTest is Test {
  PEAS public peas;
  V3TwapUtilities public twapUtils;
  UniswapDexAdapter public dexAdapter;
  WeightedIndex public pod;

  uint256 public bondAmt = 1e18;
  uint16 fee = 100;

  function setUp() public {
    peas = new PEAS('Peapods', 'PEAS');
    twapUtils = new V3TwapUtilities();
    dexAdapter = new UniswapDexAdapter(
      twapUtils,
      0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,
      0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45,
      false
    );
    IDecentralizedIndex.Config memory _c;
    IDecentralizedIndex.Fees memory _f;
    _f.bond = fee;
    _f.debond = fee;
    address[] memory _t = new address[](1);
    _t[0] = address(peas);
    uint256[] memory _w = new uint256[](1);
    _w[0] = 100;
    pod = new WeightedIndex(
      'Test',
      'pTEST',
      _c,
      _f,
      _t,
      _w,
      address(0),
      address(peas),
      address(dexAdapter),
      false
    );
  }

  function test_symbol() public view {
    assertEq(pod.symbol(), 'pTEST');
  }

  function test_bond() public {
    peas.approve(address(pod), peas.totalSupply());
    pod.bond(address(peas), bondAmt, 0);
    assertEq(pod.totalSupply(), bondAmt);
    assertEq(pod.balanceOf(address(this)), pod.totalSupply());
  }

  function test_debondFullSupply() public {
    // wrap first
    peas.approve(address(pod), peas.totalSupply());
    pod.bond(address(peas), bondAmt, 0);
    assertEq(pod.totalSupply(), bondAmt);

    // unwrap last
    address[] memory _n1;
    uint8[] memory _n2;
    pod.debond(bondAmt, _n1, _n2);
    assertEq(pod.totalSupply(), 0);
  }

  function test_debondFeeCheck() public {
    // wrap first
    peas.approve(address(pod), peas.totalSupply());
    pod.bond(address(peas), bondAmt, 0);
    assertEq(pod.totalSupply(), bondAmt);

    // unwrap half last
    address[] memory _n1;
    uint8[] memory _n2;
    pod.debond(bondAmt / 2, _n1, _n2);
    assertEq(pod.totalSupply(), bondAmt / 2 + ((bondAmt / 2) * fee) / 10000);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/interfaces/IERC20.sol';
import { Test, console2 } from 'forge-std/Test.sol';
import { PEAS } from '../contracts/PEAS.sol';
import { V3TwapUtilities } from '../contracts/twaputils/V3TwapUtilities.sol';
import { UniswapDexAdapter } from '../contracts/dex/UniswapDexAdapter.sol';
import { IDecentralizedIndex } from '../contracts/interfaces/IDecentralizedIndex.sol';
import { IStakingPoolToken } from '../contracts/interfaces/IStakingPoolToken.sol';
import { WeightedIndex } from '../contracts/WeightedIndex.sol';
import 'forge-std/console.sol';

contract WeightedIndexTest is Test {
  PEAS public peas;
  V3TwapUtilities public twapUtils;
  UniswapDexAdapter public dexAdapter;
  WeightedIndex public pod;

  address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  uint256 public bondAmt = 1e18;
  uint16 fee = 100;

  function setUp() public {
    peas = PEAS(0x02f92800F57BCD74066F5709F1Daa1A4302Df875);
    twapUtils = new V3TwapUtilities();
    dexAdapter = new UniswapDexAdapter(
      twapUtils,
      0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, // Uniswap V2 Router
      0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45, // Uniswap SwapRouter02
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
      false,
      false,
      abi.encode(
        dai,
        address(peas),
        0x6B175474E89094C44Da98b954EedeAC495271d0F,
        0x7d544DD34ABbE24C8832db27820Ff53C151e949b,
        0xEc0Eb48d2D638f241c1a7F109e38ef2901E9450F,
        0x024ff47D552cB222b265D68C7aeB26E586D5229D,
        dexAdapter
      )
    );

    deal(address(peas), address(this), bondAmt * 100);
    deal(dai, address(this), 5 * 10e18);
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

  function test_addLiquidityV2AndStake() public {
    (, uint256 uniBal, uint256 spTknBal) = _addLp();
    assertEq(pod.totalSupply(), bondAmt);
    assertEq(spTknBal, uniBal);
  }

  function test_addLpStakeAndProcessRewards() public {
    (address spTkn, , ) = _addLp();
    address tknRew = IStakingPoolToken(spTkn).poolRewards();
    assertEq(pod.totalSupply(), bondAmt);
    assertEq(peas.balanceOf(tknRew), 0);

    pod.bond(address(peas), bondAmt, 0);
    pod.transfer(address(pod), pod.balanceOf(address(this)));
    // 2nd time to trigger rewards
    pod.transfer(address(pod), pod.balanceOf(address(this)));

    console.log('Token rewards balance:', peas.balanceOf(tknRew));
    assertGt(peas.balanceOf(tknRew), 0);
  }

  function _addLp()
    internal
    returns (address spTkn, uint256 uniBal, uint256 spTknBal)
  {
    peas.approve(address(pod), peas.totalSupply());
    pod.bond(address(peas), bondAmt, 0);

    IERC20(dai).approve(address(pod), IERC20(dai).balanceOf(address(this)));
    pod.addLiquidityV2(
      pod.balanceOf(address(this)),
      IERC20(dai).balanceOf(address(this)),
      1000,
      block.timestamp
    );

    address spTknUniTkn = dexAdapter.getV2Pool(address(pod), dai);
    spTkn = pod.lpStakingPool();
    uniBal = IERC20(spTknUniTkn).balanceOf(address(this));

    IERC20(spTknUniTkn).approve(spTkn, uniBal);
    IStakingPoolToken(spTkn).stake(address(this), uniBal);
    spTknBal = IERC20(spTkn).balanceOf(address(this));
  }

  function test_totalAssets() public {
    // Bond some assets
    peas.approve(address(pod), peas.totalSupply());
    pod.bond(address(peas), bondAmt, 0);

    // Check total assets
    uint256 totalAssets = pod.totalAssets();
    uint256 totalAssetsTkn = pod.totalAssets(address(peas));
    assertEq(totalAssets, bondAmt, 'Total assets should equal bonded amount');
    assertEq(
      totalAssetsTkn,
      bondAmt,
      'Total assets should equal bonded amount for TKN'
    );
  }

  function test_totalSupply() public {
    // Bond some assets
    peas.approve(address(pod), peas.totalSupply());
    pod.bond(address(peas), bondAmt, 0);

    // Check total supply
    uint256 totalSupply = pod.totalSupply();
    assertEq(totalSupply, bondAmt, 'Total supply should equal bonded amount');
  }

  function test_convertToAssets() public {
    // Bond some assets
    peas.approve(address(pod), peas.totalSupply());
    pod.bond(address(peas), bondAmt, 0);

    // Test conversion with different amounts
    uint256 smallAmount = 1e15; // 0.001 tokens
    uint256 largeAmount = 1e21; // 1000 tokens

    uint256 smallAssets = pod.convertToAssets(smallAmount);
    uint256 largeAssets = pod.convertToAssets(largeAmount);

    assertApproxEqAbs(
      smallAssets,
      smallAmount,
      1,
      'Small amount conversion should be 1:1 (within 1 wei)'
    );
    assertApproxEqAbs(
      largeAssets,
      largeAmount,
      1,
      'Large amount conversion should be 1:1 (within 1 wei)'
    );
  }

  function test_convertToShares() public {
    // Bond some assets
    peas.approve(address(pod), peas.totalSupply());
    pod.bond(address(peas), bondAmt, 0);

    // Test conversion with different amounts
    uint256 smallAmount = 1e15; // 0.001 tokens
    uint256 largeAmount = 1e21; // 1000 tokens

    uint256 smallShares = pod.convertToShares(smallAmount);
    uint256 largeShares = pod.convertToShares(largeAmount);

    assertApproxEqAbs(
      smallShares,
      smallAmount,
      1,
      'Small amount conversion should be 1:1 (within 1 wei)'
    );
    assertApproxEqAbs(
      largeShares,
      largeAmount,
      1,
      'Large amount conversion should be 1:1 (within 1 wei)'
    );
  }
}

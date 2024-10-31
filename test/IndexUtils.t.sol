// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/console.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '../contracts/IndexUtils.sol';
import '../contracts/interfaces/IDecentralizedIndex.sol';
import '../contracts/interfaces/IStakingPoolToken.sol';
import { PodHelperTest } from './helpers/PodHelper.t.sol';

contract IndexUtilsTest is PodHelperTest {
  address peas = 0x02f92800F57BCD74066F5709F1Daa1A4302Df875;
  IndexUtils public utils;

  function setUp() public override {
    super.setUp();
    utils = new IndexUtils(
      IV3TwapUtilities(0x024ff47D552cB222b265D68C7aeB26E586D5229D),
      IDexAdapter(0x7686aa8B32AA9Eb135AC15a549ccd71976c878Bb)
    );
  }

  function test_addLPAndStake() public {
    // Get a pod to test with
    address podToDup = IStakingPoolToken(
      0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1 // spPDAI
    ).indexFund();
    address newPod = _dupPodAndSeedLp(podToDup, address(0), 0, 0);
    IDecentralizedIndex indexFund = IDecentralizedIndex(newPod);

    // Setup test amounts
    uint256 podTokensToAdd = 1e18;
    uint256 pairedTokensToAdd = 1e18;
    uint256 slippage = 1000; // 100% slippage for test

    // Deal tokens to this contract
    deal(peas, address(this), podTokensToAdd);
    IERC20(peas).approve(address(indexFund), podTokensToAdd);
    uint256 podBef = indexFund.balanceOf(address(this));
    indexFund.bond(peas, podTokensToAdd, 0);
    uint256 pTknToLp = indexFund.balanceOf(address(this)) - podBef;
    deal(indexFund.PAIRED_LP_TOKEN(), address(this), pairedTokensToAdd);

    // Get initial balances
    uint256 initialPodBalance = IERC20(address(indexFund)).balanceOf(
      address(this)
    );
    uint256 initialPairedBalance = IERC20(indexFund.PAIRED_LP_TOKEN())
      .balanceOf(address(this));

    // Approve tokens
    IERC20(address(indexFund)).approve(address(utils), pTknToLp);
    IERC20(indexFund.PAIRED_LP_TOKEN()).approve(
      address(utils),
      pairedTokensToAdd
    );

    // Get initial staked LP balance
    address stakingPool = indexFund.lpStakingPool();
    uint256 initialStakedBalance = IERC20(stakingPool).balanceOf(address(this));

    // Add liquidity and stake
    uint256 lpTokensReceived = utils.addLPAndStake(
      indexFund,
      pTknToLp,
      indexFund.PAIRED_LP_TOKEN(),
      pairedTokensToAdd,
      0, // min paired tokens
      slippage,
      block.timestamp
    );

    // Verify LP tokens were received and staked
    assertGt(lpTokensReceived, 0, 'Should receive LP tokens');
    assertGt(
      IERC20(stakingPool).balanceOf(address(this)) - initialStakedBalance,
      0,
      'Staked balance should increase'
    );

    // Verify token balances were reduced
    assertLt(
      IERC20(address(indexFund)).balanceOf(address(this)),
      initialPodBalance,
      'Pod token balance should decrease'
    );
    assertEq(
      IERC20(indexFund.PAIRED_LP_TOKEN()).balanceOf(address(this)),
      initialPairedBalance - pairedTokensToAdd,
      'Paired token balance should decrease'
    );
  }

  function test_addLPAndStake_WithEth() public {
    // Get a pod to test with
    address podToDup = IStakingPoolToken(
      0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1 // spPDAI
    ).indexFund();
    address newPod = _dupPodAndSeedLp(podToDup, address(0), 0, 0);
    IDecentralizedIndex indexFund = IDecentralizedIndex(newPod);

    // Setup test amounts
    uint256 podTokensToAdd = 1e18;
    uint256 ethToAdd = 1 ether;
    uint256 slippage = 1000; // 100% slippage for test

    // Deal tokens to this contract
    deal(peas, address(this), podTokensToAdd);
    IERC20(peas).approve(address(indexFund), podTokensToAdd);
    uint256 podBef = indexFund.balanceOf(address(this));
    indexFund.bond(peas, podTokensToAdd, 0);
    uint256 pTknToLp = indexFund.balanceOf(address(this)) - podBef;
    vm.deal(address(this), ethToAdd);

    // Get initial balances
    uint256 initialPodBalance = IERC20(address(indexFund)).balanceOf(
      address(this)
    );
    uint256 initialEthBalance = address(this).balance;

    // Approve tokens
    IERC20(address(indexFund)).approve(address(utils), pTknToLp);

    // Get initial staked LP balance
    address stakingPool = indexFund.lpStakingPool();
    uint256 initialStakedBalance = IERC20(stakingPool).balanceOf(address(this));

    // Add liquidity and stake with ETH
    uint256 lpTokensReceived = utils.addLPAndStake{ value: ethToAdd }(
      indexFund,
      pTknToLp,
      address(0), // Use ETH
      ethToAdd,
      0, // min paired tokens
      slippage,
      block.timestamp
    );

    // Verify LP tokens were received and staked
    assertGt(lpTokensReceived, 0, 'Should receive LP tokens');
    assertGt(
      IERC20(stakingPool).balanceOf(address(this)) - initialStakedBalance,
      0,
      'Staked balance should increase'
    );

    // Verify token balances were reduced
    assertLt(
      IERC20(address(indexFund)).balanceOf(address(this)),
      initialPodBalance,
      'Pod token balance should decrease'
    );
    assertLt(
      address(this).balance,
      initialEthBalance,
      'ETH balance should decrease'
    );
  }

  receive() external payable {}
}

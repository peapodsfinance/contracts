// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';
import { IERC20 } from '@openzeppelin/contracts/interfaces/IERC20.sol';
import { IDecentralizedIndex } from '../contracts/interfaces/IDecentralizedIndex.sol';
import { IIndexUtils_LEGACY } from '../contracts/interfaces/IIndexUtils_LEGACY.sol';
import { IIndexUtils } from '../contracts/interfaces/IIndexUtils.sol';
import { AutoCompoundingPodLp } from '../contracts/AutoCompoundingPodLp.sol';
import { RewardsWhitelist } from '../contracts/RewardsWhitelist.sol';
import { WeightedIndex } from '../contracts/WeightedIndex.sol';
import { PEAS } from '../contracts/PEAS.sol';
import { V3TwapUtilities } from '../contracts/twaputils/V3TwapUtilities.sol';
import { UniswapDexAdapter } from '../contracts/dex/UniswapDexAdapter.sol';
import { BalancerFlashSource } from '../contracts/flash/BalancerFlashSource.sol';
import { LeverageManager } from '../contracts/lvf/LeverageManager.sol';
import { MockFraxlendPair } from './mocks/MockFraxlendPair.sol';
import 'forge-std/console.sol';

contract LeverageManagerTest is Test {
  IIndexUtils_LEGACY public idxUtils;
  BalancerFlashSource public flashSource;
  AutoCompoundingPodLp public aspTkn;
  LeverageManager public leverageManager;
  MockFraxlendPair public mockFraxlendPair;
  PEAS public peas;
  RewardsWhitelist public whitelister;
  V3TwapUtilities public twapUtils;
  UniswapDexAdapter public dexAdapter;
  WeightedIndex public pod;

  address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  address public spTkn;

  address public constant ALICE = address(0x1);
  address public constant BOB = address(0x2);
  uint256 public constant INITIAL_BALANCE = 1000000 * 1e18;

  function setUp() public {
    uint16 fee = 100;
    peas = PEAS(0x02f92800F57BCD74066F5709F1Daa1A4302Df875);
    whitelister = new RewardsWhitelist();
    twapUtils = new V3TwapUtilities();
    dexAdapter = new UniswapDexAdapter(
      twapUtils,
      0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, // Uniswap V2 Router
      0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45, // Uniswap SwapRouter02
      false
    );
    // idxUtils = new IndexUtils(twapUtils, dexAdapter);
    idxUtils = IIndexUtils_LEGACY(0x9A103aB4FE2De5db16338B16FD7550D21d7b8DB6);
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
        whitelister,
        0x024ff47D552cB222b265D68C7aeB26E586D5229D,
        dexAdapter
      )
    );

    spTkn = pod.lpStakingPool();
    aspTkn = new AutoCompoundingPodLp(
      'aspTKN',
      'aspTKN',
      false,
      pod,
      dexAdapter,
      IIndexUtils(address(idxUtils))
    );

    // Deploy MockFraxlendPair
    mockFraxlendPair = new MockFraxlendPair(dai, address(aspTkn));

    // Supply borrow asset to pair
    deal(dai, address(this), 1e9 * 1e18);
    IERC20(dai).approve(address(mockFraxlendPair), 1e9 * 1e18);
    mockFraxlendPair.deposit(1e9 * 1e18, address(this));

    // Deploy LeverageManager
    leverageManager = new LeverageManager('Leverage Position', 'LP', idxUtils);
    flashSource = new BalancerFlashSource(address(leverageManager));

    // Setup LeverageManager
    leverageManager.setLendingPair(address(pod), address(mockFraxlendPair));
    leverageManager.setFlashSource(dai, address(flashSource));

    // Approve LeverageManager to spend tokens
    vm.startPrank(ALICE);
    pod.approve(address(leverageManager), type(uint256).max);
    IERC20(dai).approve(address(leverageManager), type(uint256).max);
    vm.stopPrank();

    vm.startPrank(BOB);
    pod.approve(address(leverageManager), type(uint256).max);
    IERC20(dai).approve(address(leverageManager), type(uint256).max);
    vm.stopPrank();
  }

  function test_addLeverage() public {
    uint256 pTknAmt = 100 * 1e18;
    uint256 pairedLpDesired = 50 * 1e18;
    uint256 pairedLpAmtMin = 45 * 1e18;
    bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

    deal(address(peas), ALICE, pTknAmt * 100);

    vm.startPrank(ALICE);

    // wrap into the pod
    peas.approve(address(pod), peas.totalSupply());
    pod.bond(address(peas), pTknAmt, 0);

    uint256 positionId = leverageManager.initializePosition(
      address(pod),
      ALICE,
      address(0),
      address(0)
    );

    uint256 alicePodTokenBalanceBefore = pod.balanceOf(ALICE);
    uint256 aliceAssetBalanceBefore = IERC20(dai).balanceOf(ALICE);

    leverageManager.addLeverage(
      positionId,
      address(pod),
      pTknAmt,
      pairedLpDesired,
      pairedLpAmtMin,
      address(0),
      config
    );

    vm.stopPrank();

    // Verify the position NFT was minted
    assertEq(
      leverageManager.positionNFT().ownerOf(positionId),
      ALICE,
      'Position NFT not minted to ALICE'
    );

    // Verify the balance changes in the mock contracts
    assertEq(
      pod.balanceOf(ALICE),
      alicePodTokenBalanceBefore - pTknAmt,
      'Incorrect Pod Token balance after adding leverage'
    );
    assertEq(
      IERC20(dai).balanceOf(ALICE),
      aliceAssetBalanceBefore,
      'Asset balance should not change for ALICE'
    );

    // Verify the state of the LeverageManager contract
    (
      address returnedPod,
      address lendingPair,
      address custodian,
      bool isSelfLending,
      address selfLendingPod
    ) = leverageManager.positionProps(positionId);
    assertEq(returnedPod, address(pod), 'Incorrect pod address');
    assertEq(
      lendingPair,
      address(mockFraxlendPair),
      'Incorrect lending pair address'
    );
    assertNotEq(custodian, address(0), 'Custodian address should not be zero');
    assertEq(isSelfLending, false, 'Not self lending');
    assertEq(selfLendingPod, address(0), 'Self lending pod should be zero');
  }

  // function testAddLeverageMaxAmount() public {
  //   uint256 pTknAmt = INITIAL_BALANCE;
  //   uint256 pairedLpDesired = INITIAL_BALANCE / 2;
  //   uint256 pairedLpAmtMin = (INITIAL_BALANCE * 45) / 100;
  //   bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

  //   vm.startPrank(ALICE);

  //   uint256 positionId = leverageManager.initializePosition(
  //     address(mockDecentralizedIndex),
  //     ALICE,address(0),
  //     address(0)
  //   );

  //   leverageManager.addLeverage(
  //     positionId,
  //     address(mockDecentralizedIndex),
  //     pTknAmt,
  //     pairedLpDesired,
  //     pairedLpAmtMin,
  //     address(0),
  //     config
  //   );

  //   vm.stopPrank();

  //   assertEq(
  //     mockPodToken.balanceOf(ALICE),
  //     0,
  //     'ALICE should have zero Pod Token balance after adding max leverage'
  //   );
  // }

  // function testAddLeverageMinAmount() public {
  //   uint256 pTknAmt = 1;
  //   uint256 pairedLpDesired = 1;
  //   uint256 pairedLpAmtMin = 1;
  //   bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

  //   vm.startPrank(ALICE);

  //   uint256 positionId = leverageManager.initializePosition(
  //     address(mockDecentralizedIndex),
  //     ALICE,address(0),
  //     address(0)
  //   );

  //   leverageManager.addLeverage(
  //     positionId,
  //     address(mockDecentralizedIndex),
  //     pTknAmt,
  //     pairedLpDesired,
  //     pairedLpAmtMin,
  //     address(0),
  //     config
  //   );

  //   vm.stopPrank();

  //   assertEq(
  //     mockPodToken.balanceOf(ALICE),
  //     INITIAL_BALANCE - 1,
  //     'ALICE should have initial balance minus 1 Pod Token after adding min leverage'
  //   );
  // }

  function testAddLeverageInvalidPositionId() public {
    uint256 pTknAmt = 100 * 1e18;
    uint256 pairedLpDesired = 50 * 1e18;
    uint256 pairedLpAmtMin = 45 * 1e18;
    bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

    deal(address(peas), ALICE, pTknAmt * 100);

    vm.startPrank(ALICE);

    // wrap into the pod
    peas.approve(address(pod), peas.totalSupply());
    pod.bond(address(peas), pTknAmt, 0);

    uint256 invalidPositionId = 999; // Assume this position ID doesn't exist

    vm.expectRevert(); // We expect this call to revert due to invalid position ID
    leverageManager.addLeverage(
      invalidPositionId,
      address(pod),
      pTknAmt,
      pairedLpDesired,
      pairedLpAmtMin,
      address(0),
      config
    );

    vm.stopPrank();
  }

  function testAddLeverageInsufficientBalance() public {
    uint256 pTknAmt = 100 * 1e18;
    uint256 pairedLpDesired = 50 * 1e18;
    uint256 pairedLpAmtMin = 45 * 1e18;
    bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

    deal(address(peas), ALICE, pTknAmt);

    vm.startPrank(ALICE);

    // wrap into the pod
    peas.approve(address(pod), peas.totalSupply());
    pod.bond(address(peas), pTknAmt, 0);

    // burn 1 pTKN so we have less than we need
    pod.burn(1);

    uint256 positionId = leverageManager.initializePosition(
      address(pod),
      ALICE,
      address(0),
      address(0)
    );

    vm.expectRevert(); // We expect this call to revert due to insufficient balance
    leverageManager.addLeverage(
      positionId,
      address(pod),
      pTknAmt,
      pairedLpDesired,
      pairedLpAmtMin,
      address(0),
      config
    );

    vm.stopPrank();
  }

  function testAddLeverageUnauthorized() public {
    uint256 pTknAmt = 100 * 1e18;
    uint256 pairedLpDesired = 50 * 1e18;
    uint256 pairedLpAmtMin = 45 * 1e18;
    bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

    deal(address(peas), ALICE, pTknAmt * 100);

    vm.startPrank(ALICE);

    // wrap into the pod
    peas.approve(address(pod), peas.totalSupply());
    pod.bond(address(peas), pTknAmt, 0);

    uint256 positionId = leverageManager.initializePosition(
      address(pod),
      ALICE,
      address(0),
      address(0)
    );
    vm.stopPrank();

    vm.startPrank(BOB);
    vm.expectRevert(); // We expect this call to revert due to unauthorized access
    leverageManager.addLeverage(
      positionId,
      address(pod),
      pTknAmt,
      pairedLpDesired,
      pairedLpAmtMin,
      address(0),
      config
    );
    vm.stopPrank();
  }

  // function testAddLeverageFlashLoanInteraction() public {
  //   uint256 pTknAmt = 100 * 1e18;
  //   uint256 pairedLpDesired = 50 * 1e18;
  //   uint256 pairedLpAmtMin = 45 * 1e18;
  //   bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

  //   vm.startPrank(ALICE);
  //   uint256 positionId = leverageManager.initializePosition(
  //     address(mockDecentralizedIndex),
  //     ALICE,address(0),
  //     address(0)
  //   );

  //   // Mock the flash loan interaction
  //   mockFlashLoanSource.expectFlash(
  //     address(mockAsset),
  //     pairedLpDesired,
  //     address(leverageManager),
  //     abi.encode(
  //       LeverageManager.LeverageFlashProps({
  //         method: LeverageManager.FlashCallbackMethod.ADD,
  //         positionId: positionId,
  //         user: ALICE,
  //         pTknAmt: pTknAmt,
  //         pairedLpDesired: pairedLpDesired,
  //         pairedLpAmtMin: pairedLpAmtMin,
  //         selfLendingPairPod: address(0),
  //         config: config
  //       }),
  //       ''
  //     )
  //   );

  //   leverageManager.addLeverage(
  //     positionId,
  //     address(mockDecentralizedIndex),
  //     pTknAmt,
  //     pairedLpDesired,
  //     pairedLpAmtMin,
  //     address(0),
  //     config
  //   );

  //   vm.stopPrank();

  //   // Verify that the flash loan was called with the expected parameters
  //   mockFlashLoanSource.verifyFlash();
  // }

  // function testAddLeverageWithSelfLendingPod() public {
  //   uint256 pTknAmt = 100 * 1e18;
  //   uint256 pairedLpDesired = 50 * 1e18;
  //   uint256 pairedLpAmtMin = 45 * 1e18;
  //   bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

  //   address mockSelfLendingPod = address(new MockDecentralizedIndex());

  //   vm.startPrank(ALICE);
  //   uint256 positionId = leverageManager.initializePosition(
  //     address(mockDecentralizedIndex),
  //     ALICE,address(0),
  //     mockSelfLendingPod
  //   );

  //   leverageManager.addLeverage(
  //     positionId,
  //     address(mockDecentralizedIndex),
  //     pTknAmt,
  //     pairedLpDesired,
  //     pairedLpAmtMin,
  //     mockSelfLendingPod,
  //     config
  //   );

  //   vm.stopPrank();

  //   // Verify that the self lending pod was set correctly
  //   (, , , address selfLendingPod) = leverageManager.positionProps(positionId);
  //   assertEq(
  //     selfLendingPod,
  //     mockSelfLendingPod,
  //     'Self lending pod not set correctly'
  //   );
  // }

  // function testAddLeverageSlippageLimit() public {
  //   uint256 pTknAmt = 100 * 1e18;
  //   uint256 pairedLpDesired = 50 * 1e18;
  //   uint256 pairedLpAmtMin = 49 * 1e18; // Set a high minimum to trigger slippage protection
  //   bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

  //   // Configure MockIndexUtils to return less than the minimum
  //   mockIndexUtils.setAddLPAndStakeReturn(48 * 1e18);

  //   vm.startPrank(ALICE);
  //   uint256 positionId = leverageManager.initializePosition(
  //     address(mockDecentralizedIndex),
  //     ALICE,address(0),
  //     address(0)
  //   );

  //   vm.expectRevert('Slippage limit reached');
  //   leverageManager.addLeverage(
  //     positionId,
  //     address(mockDecentralizedIndex),
  //     pTknAmt,
  //     pairedLpDesired,
  //     pairedLpAmtMin,
  //     address(0),
  //     config
  //   );

  //   vm.stopPrank();
  // }

  function testAddLeverageWithOpenFee() public {
    uint256 pTknAmt = 100 * 1e18;
    uint256 pairedLpDesired = 50 * 1e18;
    uint256 pairedLpAmtMin = 45 * 1e18;
    bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

    deal(address(peas), ALICE, pTknAmt * 100);

    uint16 openFeePerc = 100; // 10% open fee

    // Set open fee
    leverageManager.setOpenFeePerc(openFeePerc);

    uint256 _adminAspBalBefore = aspTkn.balanceOf(address(this));

    vm.startPrank(ALICE);

    // wrap into the pod
    peas.approve(address(pod), peas.totalSupply());
    pod.bond(address(peas), pTknAmt, 0);

    uint256 positionId = leverageManager.initializePosition(
      address(pod),
      ALICE,
      address(0),
      address(0)
    );

    uint256 alicePodTokenBalanceBefore = pod.balanceOf(ALICE);

    leverageManager.addLeverage(
      positionId,
      address(pod),
      pTknAmt,
      pairedLpDesired,
      pairedLpAmtMin,
      address(0),
      config
    );

    vm.stopPrank();

    // Verify the open fee was charged
    assertEq(
      pod.balanceOf(ALICE),
      alicePodTokenBalanceBefore - pTknAmt,
      'Incorrect Pod Token balance after adding leverage'
    );
    assertGt(
      aspTkn.balanceOf(address(this)),
      _adminAspBalBefore,
      'Protocol fee successfully collected'
    );
  }
}

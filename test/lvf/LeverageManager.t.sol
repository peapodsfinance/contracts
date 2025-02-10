// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IDecentralizedIndex} from "../../contracts/interfaces/IDecentralizedIndex.sol";
import {IIndexUtils} from "../../contracts/interfaces/IIndexUtils.sol";
import {IndexUtils} from "../../contracts/IndexUtils.sol";
import {AutoCompoundingPodLp} from "../../contracts/AutoCompoundingPodLp.sol";
import {RewardsWhitelist} from "../../contracts/RewardsWhitelist.sol";
import {WeightedIndex} from "../../contracts/WeightedIndex.sol";
import {PEAS} from "../../contracts/PEAS.sol";
import {V3TwapUtilities} from "../../contracts/twaputils/V3TwapUtilities.sol";
import {UniswapDexAdapter} from "../../contracts/dex/UniswapDexAdapter.sol";
import {BalancerFlashSource} from "../../contracts/flash/BalancerFlashSource.sol";
import {PodFlashMintSource} from "../../contracts/flash/PodFlashMintSource.sol";
import {LeverageManager} from "../../contracts/lvf/LeverageManager.sol";
import {MockFraxlendPair} from "../mocks/MockFraxlendPair.sol";
import {PodHelperTest} from "../helpers/PodHelper.t.sol";
import {LVFHelper} from "../helpers/LVFHelper.t.sol";

contract LeverageManagerTest is LVFHelper, PodHelperTest {
    IIndexUtils public idxUtils;
    BalancerFlashSource public flashSource;
    PodFlashMintSource public flashMintSource;
    AutoCompoundingPodLp public aspTkn;
    AutoCompoundingPodLp public aspTkn2;
    LeverageManager public leverageManager;
    MockFraxlendPair public mockFraxlendPair;
    MockFraxlendPair public mockFraxlendPair2;
    PEAS public peas;
    RewardsWhitelist public whitelister;
    V3TwapUtilities public twapUtils;
    UniswapDexAdapter public dexAdapter;
    WeightedIndex public pod;
    WeightedIndex public pairedLpPod;
    WeightedIndex public podWithPairedAsPod;

    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public spTkn;
    address public spTkn2;

    address public constant ALICE = address(0x1);
    address public constant BOB = address(0x2);
    uint256 public constant INITIAL_BALANCE = 1000000 * 1e18;

    function setUp() public override {
        super.setUp();
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
        idxUtils = new IndexUtils(twapUtils, dexAdapter);
        IDecentralizedIndex.Config memory _c;
        IDecentralizedIndex.Fees memory _f;
        _f.bond = fee;
        _f.debond = fee;
        address[] memory _t = new address[](1);
        _t[0] = address(peas);
        uint256[] memory _w = new uint256[](1);
        _w[0] = 100;
        address _pod = _createPod(
            "Test",
            "pTEST",
            _c,
            _f,
            _t,
            _w,
            address(0),
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
        pod = WeightedIndex(payable(_pod));
        pairedLpPod = WeightedIndex(payable(_createSimplePod(usdc, dai)));
        podWithPairedAsPod = WeightedIndex(payable(_createSimplePod(address(peas), address(pairedLpPod))));

        spTkn = pod.lpStakingPool();
        aspTkn = new AutoCompoundingPodLp("aspTKN", "aspTKN", false, pod, dexAdapter, idxUtils);
        spTkn2 = pod.lpStakingPool();
        aspTkn2 = new AutoCompoundingPodLp("aspTKN2", "aspTKN2", false, podWithPairedAsPod, dexAdapter, idxUtils);

        // Deploy MockFraxlendPair
        mockFraxlendPair = new MockFraxlendPair(dai, address(aspTkn));
        mockFraxlendPair2 = new MockFraxlendPair(address(pairedLpPod), address(aspTkn2));

        // Supply borrow asset to pair
        deal(dai, address(this), 1e9 * 1e18);
        IERC20(dai).approve(address(mockFraxlendPair), 1e9 * 1e18);
        mockFraxlendPair.deposit(1e9 * 1e18, address(this));

        // Supply borrow asset to pair2
        deal(address(usdc), address(this), 1e9 * 1e18);
        IERC20(usdc).approve(address(pairedLpPod), 1e9 * 1e18);
        pairedLpPod.bond(address(usdc), 1e9 * 1e18, 0);
        pairedLpPod.approve(address(mockFraxlendPair2), 1e9 * 1e18);
        mockFraxlendPair2.deposit(1e9 * 1e18, address(this));

        // Deploy LeverageManager
        leverageManager =
            LeverageManager(_deployLeverageManager("Leverage Position", "LP", address(idxUtils), address(this)));
        flashSource = new BalancerFlashSource(address(leverageManager));
        flashMintSource = new PodFlashMintSource(address(pairedLpPod), address(leverageManager));

        // Setup LeverageManager
        leverageManager.setLendingPair(address(pod), address(mockFraxlendPair));
        leverageManager.setLendingPair(address(podWithPairedAsPod), address(mockFraxlendPair2));
        leverageManager.setFlashSource(dai, address(flashSource));
        leverageManager.setFlashSource(address(pairedLpPod), address(flashMintSource));

        // Approve LeverageManager to spend tokens
        vm.startPrank(ALICE);
        pod.approve(address(leverageManager), type(uint256).max);
        podWithPairedAsPod.approve(address(leverageManager), type(uint256).max);
        IERC20(dai).approve(address(leverageManager), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(BOB);
        pod.approve(address(leverageManager), type(uint256).max);
        podWithPairedAsPod.approve(address(leverageManager), type(uint256).max);
        IERC20(dai).approve(address(leverageManager), type(uint256).max);
        vm.stopPrank();
    }

    function test_addLeverage() public {
        uint256 pTknAmt = 100 * 1e18;
        uint256 pairedLpDesired = 50 * 1e18;
        bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

        deal(address(peas), ALICE, pTknAmt * 100);

        vm.startPrank(ALICE);

        // wrap into the pod
        peas.approve(address(pod), peas.totalSupply());
        pod.bond(address(peas), pTknAmt, 0);

        uint256 positionId = leverageManager.initializePosition(address(pod), ALICE, false);

        uint256 alicePodTokenBalanceBefore = pod.balanceOf(ALICE);
        uint256 aliceAssetBalanceBefore = IERC20(dai).balanceOf(ALICE);

        leverageManager.addLeverage(positionId, address(pod), pTknAmt, pairedLpDesired, 0, false, config);

        vm.stopPrank();

        // Verify the position NFT was minted
        assertEq(leverageManager.positionNFT().ownerOf(positionId), ALICE, "Position NFT not minted to ALICE");

        // Verify the balance changes in the mock contracts
        assertEq(
            pod.balanceOf(ALICE),
            alicePodTokenBalanceBefore - pTknAmt,
            "Incorrect Pod Token balance after adding leverage"
        );
        assertEq(IERC20(dai).balanceOf(ALICE), aliceAssetBalanceBefore, "Asset balance should not change for ALICE");

        // Verify the state of the LeverageManager contract
        (address returnedPod, address lendingPair, address custodian, bool isSelfLending, bool hasSelfLendingPairPod) =
            leverageManager.positionProps(positionId);
        assertEq(returnedPod, address(pod), "Incorrect pod address");
        assertEq(lendingPair, address(mockFraxlendPair), "Incorrect lending pair address");
        assertNotEq(custodian, address(0), "Custodian address should not be zero");
        assertEq(isSelfLending, false, "Not self lending");
        assertEq(hasSelfLendingPairPod, false, "Self lending pod should be zero");
    }

    function test_addLeverage_RemoveLeverageWithUserProvidedDebt() public {
        uint256 pTknAmt = 100 * 1e18;
        uint256 pairedLpDesired = 50 * 1e18;
        bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

        deal(address(peas), ALICE, pTknAmt * 100);

        vm.startPrank(ALICE);

        // wrap into the pod
        peas.approve(address(pod), peas.totalSupply());
        pod.bond(address(peas), pTknAmt, 0);

        uint256 positionId = leverageManager.initializePosition(address(pod), ALICE, false);

        uint256 alicePodTokenBalanceBefore = pod.balanceOf(ALICE);
        uint256 aliceAssetBalanceBefore = IERC20(dai).balanceOf(ALICE);

        // add to newly created position
        leverageManager.addLeverage(positionId, address(pod), pTknAmt, pairedLpDesired, 0, false, config);

        (, address lendingPair, address custodian,,) = leverageManager.positionProps(positionId);

        // remove from position
        IERC20(dai).approve(address(leverageManager), pairedLpDesired);
        leverageManager.removeLeverage(
            positionId,
            pairedLpDesired / 2,
            abi.encode(MockFraxlendPair(lendingPair).userCollateralBalance(custodian) / 2, 0, 0, 0, pairedLpDesired)
        );

        vm.stopPrank();

        // Verify the position NFT was minted
        assertEq(leverageManager.positionNFT().ownerOf(positionId), ALICE, "Position NFT not minted to ALICE");

        // Verify the balance changes in the mock contracts
        assertGt(
            pod.balanceOf(ALICE),
            alicePodTokenBalanceBefore - pTknAmt,
            "Pod Token balance should be more than amount after adding leverage, then removing leverage"
        );
        assertLe(
            IERC20(dai).balanceOf(ALICE),
            aliceAssetBalanceBefore,
            "Asset balance should be equal or less for ALICE when paying off position with user provided debt"
        );

        // Verify the state of the LeverageManager contract
        assertEq(lendingPair, address(mockFraxlendPair), "Incorrect lending pair address");
        assertNotEq(custodian, address(0), "Custodian address should not be zero");
    }

    function test_addLeverage_RemoveLeverageWithSwap() public {
        uint256 pTknAmt = 100 * 1e18;
        uint256 pairedLpDesired = 50 * 1e18;
        bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

        deal(address(peas), ALICE, pTknAmt * 100);

        vm.startPrank(ALICE);

        // wrap into the pod
        peas.approve(address(pod), peas.totalSupply());
        pod.bond(address(peas), pTknAmt, 0);

        uint256 positionId = leverageManager.initializePosition(address(pod), ALICE, false);

        uint256 alicePodTokenBalanceBefore = pod.balanceOf(ALICE);
        uint256 aliceAssetBalanceBefore = IERC20(dai).balanceOf(ALICE);

        // add to newly created position
        leverageManager.addLeverage(positionId, address(pod), pTknAmt, pairedLpDesired, 0, false, config);

        (address returnedPod, address lendingPair, address custodian, bool isSelfLending, bool hasSelfLendingPairPod) =
            leverageManager.positionProps(positionId);

        // remove from position
        leverageManager.removeLeverage(
            positionId,
            pairedLpDesired / 2,
            abi.encode(MockFraxlendPair(lendingPair).userCollateralBalance(custodian) / 2, 0, 0, 0, 0)
        );

        vm.stopPrank();

        // Verify the position NFT was minted
        assertEq(leverageManager.positionNFT().ownerOf(positionId), ALICE, "Position NFT not minted to ALICE");

        // Verify the balance changes in the mock contracts
        assertEq(
            pod.balanceOf(ALICE),
            alicePodTokenBalanceBefore - pTknAmt,
            "Incorrect Pod Token balance after adding leverage then removing leverage with 100% slippage from pTKN > borrowTkn swap"
        );
        assertGe(
            IERC20(dai).balanceOf(ALICE), aliceAssetBalanceBefore, "Asset balance should be equal or more for ALICE"
        );

        // Verify the state of the LeverageManager contract
        assertEq(returnedPod, address(pod), "Incorrect pod address");
        assertEq(lendingPair, address(mockFraxlendPair), "Incorrect lending pair address");
        assertNotEq(custodian, address(0), "Custodian address should not be zero");
        assertEq(isSelfLending, false, "Not self lending");
        assertEq(hasSelfLendingPairPod, false, "Self lending pod should be zero");
    }

    function test_addLeverage_PodFlashMintForPairedLpTkn() public {
        uint256 pTknAmt = 100 * 1e18;
        uint256 pairedLpDesired = 50 * 1e18;
        bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

        deal(address(peas), ALICE, pTknAmt * 100);

        vm.startPrank(ALICE);

        // wrap into the pod
        peas.approve(address(podWithPairedAsPod), peas.totalSupply());
        podWithPairedAsPod.bond(address(peas), pTknAmt, 0);

        uint256 positionId = leverageManager.initializePosition(address(podWithPairedAsPod), ALICE, false);

        uint256 alicePodTokenBalanceBefore = podWithPairedAsPod.balanceOf(ALICE);
        uint256 aliceAssetBalanceBefore = IERC20(pairedLpPod).balanceOf(ALICE);
        uint256 pairedPodSupplyBefore = pairedLpPod.totalSupply();

        leverageManager.addLeverage(positionId, address(podWithPairedAsPod), pTknAmt, pairedLpDesired, 0, false, config);

        vm.stopPrank();

        assertEq(
            pairedLpPod.totalSupply(),
            pairedPodSupplyBefore - (pairedLpDesired / 1000),
            "flashMint fee for pairedLpPod was not handled as expected"
        );

        // Verify the position NFT was minted
        assertEq(leverageManager.positionNFT().ownerOf(positionId), ALICE, "Position NFT not minted to ALICE");

        // Verify the balance changes in the mock contracts
        assertEq(
            podWithPairedAsPod.balanceOf(ALICE),
            alicePodTokenBalanceBefore - pTknAmt,
            "Incorrect Pod Token balance after adding leverage"
        );
        assertEq(
            IERC20(pairedLpPod).balanceOf(ALICE), aliceAssetBalanceBefore, "Asset balance should not change for ALICE"
        );

        // Verify the state of the LeverageManager contract
        (address returnedPod, address lendingPair, address custodian, bool isSelfLending, bool hasSelfLendingPairPod) =
            leverageManager.positionProps(positionId);
        assertEq(returnedPod, address(podWithPairedAsPod), "Incorrect pod address");
        assertEq(lendingPair, address(mockFraxlendPair2), "Incorrect lending pair address");
        assertNotEq(custodian, address(0), "Custodian address should not be zero");
        assertEq(isSelfLending, false, "Not self lending");
        assertEq(hasSelfLendingPairPod, false, "Self lending pod should be zero");
    }

    function test_addLeverage_WithOpenFee() public {
        leverageManager.setOpenFeePerc(100);

        uint256 pTknAmt = 100 * 1e18;
        uint256 pairedLpDesired = 50 * 1e18;
        bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

        deal(address(peas), ALICE, pTknAmt * 100);

        vm.startPrank(ALICE);

        // wrap into the pod
        peas.approve(address(pod), peas.totalSupply());
        pod.bond(address(peas), pTknAmt, 0);

        uint256 positionId = leverageManager.initializePosition(address(pod), ALICE, false);

        uint256 alicePodTokenBalanceBefore = pod.balanceOf(ALICE);
        uint256 aliceAssetBalanceBefore = IERC20(dai).balanceOf(ALICE);

        leverageManager.addLeverage(positionId, address(pod), pTknAmt, pairedLpDesired, 0, false, config);

        vm.stopPrank();

        // Verify the position NFT was minted
        assertEq(leverageManager.positionNFT().ownerOf(positionId), ALICE, "Position NFT not minted to ALICE");

        // Verify the balance changes in the mock contracts
        assertEq(
            pod.balanceOf(ALICE),
            alicePodTokenBalanceBefore - pTknAmt,
            "Incorrect Pod Token balance after adding leverage"
        );
        assertEq(IERC20(dai).balanceOf(ALICE), aliceAssetBalanceBefore, "Asset balance should not change for ALICE");

        // Verify the state of the LeverageManager contract
        (address returnedPod, address lendingPair, address custodian, bool isSelfLending, bool hasSelfLendingPairPod) =
            leverageManager.positionProps(positionId);
        assertEq(returnedPod, address(pod), "Incorrect pod address");
        assertEq(lendingPair, address(mockFraxlendPair), "Incorrect lending pair address");
        assertNotEq(custodian, address(0), "Custodian address should not be zero");
        assertEq(isSelfLending, false, "Not self lending");
        assertEq(hasSelfLendingPairPod, false, "Self lending pod should be zero");
    }

    function test_addLeverageFromTkn() public {
        uint256 tknAmt = 100 * 1e18;
        // uint256 ptknAmt = pod.convertToShares(tknAmt);
        uint256 pairedLpDesired = 50 * 1e18;
        bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

        deal(address(peas), ALICE, tknAmt * 100);

        vm.startPrank(ALICE);

        uint256 positionId = leverageManager.initializePosition(address(pod), ALICE, false);

        uint256 alicePeasTokenBalanceBefore = peas.balanceOf(ALICE);
        // uint256 alicePodTokenBalanceBefore = pod.balanceOf(ALICE);
        uint256 aliceAssetBalanceBefore = IERC20(dai).balanceOf(ALICE);

        peas.approve(address(leverageManager), tknAmt);
        leverageManager.addLeverageFromTkn(positionId, address(pod), tknAmt, 0, pairedLpDesired, 0, false, config);

        vm.stopPrank();

        // Verify the position NFT was minted
        assertEq(leverageManager.positionNFT().ownerOf(positionId), ALICE, "Position NFT not minted to ALICE");

        // Verify the balance changes in the mock contracts
        assertEq(
            peas.balanceOf(ALICE),
            alicePeasTokenBalanceBefore - tknAmt,
            "Incorrect PEAS Token balance after adding leverage"
        );
        // assertEq(
        //     pod.balanceOf(ALICE),
        //     alicePodTokenBalanceBefore - ptknAmt,
        //     "Incorrect Pod Token balance after adding leverage"
        // );
        assertEq(IERC20(dai).balanceOf(ALICE), aliceAssetBalanceBefore, "Asset balance should not change for ALICE");

        // Verify the state of the LeverageManager contract
        (address returnedPod, address lendingPair, address custodian, bool isSelfLending, bool hasSelfLendingPairPod) =
            leverageManager.positionProps(positionId);
        assertEq(returnedPod, address(pod), "Incorrect pod address");
        assertEq(lendingPair, address(mockFraxlendPair), "Incorrect lending pair address");
        assertNotEq(custodian, address(0), "Custodian address should not be zero");
        assertEq(isSelfLending, false, "Not self lending");
        assertEq(hasSelfLendingPairPod, false, "Self lending pod should be zero");
    }

    // function testAddLeverageMaxAmount() public {
    //   uint256 pTknAmt = INITIAL_BALANCE;
    //   uint256 pairedLpDesired = INITIAL_BALANCE / 2;
    //   uint256 pairedLpAmtMin = (INITIAL_BALANCE * 45) / 100;
    //   bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

    //   vm.startPrank(ALICE);

    //   uint256 positionId = leverageManager.initializePosition(
    //     address(mockDecentralizedIndex),
    //     ALICE,
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
    //     ALICE,
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
            invalidPositionId, address(pod), pTknAmt, pairedLpDesired, pairedLpAmtMin, false, config
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

        uint256 positionId = leverageManager.initializePosition(address(pod), ALICE, false);

        vm.expectRevert(); // We expect this call to revert due to insufficient balance
        leverageManager.addLeverage(positionId, address(pod), pTknAmt, pairedLpDesired, pairedLpAmtMin, false, config);

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

        uint256 positionId = leverageManager.initializePosition(address(pod), ALICE, false);
        vm.stopPrank();

        vm.startPrank(BOB);
        vm.expectRevert(); // We expect this call to revert due to unauthorized access
        leverageManager.addLeverage(positionId, address(pod), pTknAmt, pairedLpDesired, pairedLpAmtMin, false, config);
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
    //     ALICE,
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
    //     false,
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
    //     ALICE,
    //     mockSelfLendingPod
    //   );

    //   leverageManager.addLeverage(
    //     positionId,
    //     address(mockDecentralizedIndex),
    //     pTknAmt,
    //     pairedLpDesired,
    //     pairedLpAmtMin,
    //     false,
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
    //     ALICE,
    //     address(0)
    //   );

    //   vm.expectRevert('Slippage limit reached');
    //   leverageManager.addLeverage(
    //     positionId,
    //     address(mockDecentralizedIndex),
    //     pTknAmt,
    //     pairedLpDesired,
    //     pairedLpAmtMin,
    //     false,
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

        uint256 _adminDaiBalBefore = IERC20(dai).balanceOf(address(this));

        vm.startPrank(ALICE);

        // wrap into the pod
        peas.approve(address(pod), peas.totalSupply());
        pod.bond(address(peas), pTknAmt, 0);

        uint256 positionId = leverageManager.initializePosition(address(pod), ALICE, false);

        uint256 alicePodTokenBalanceBefore = pod.balanceOf(ALICE);

        leverageManager.addLeverage(positionId, address(pod), pTknAmt, pairedLpDesired, pairedLpAmtMin, false, config);

        vm.stopPrank();

        // Verify the open fee was charged
        assertEq(
            pod.balanceOf(ALICE),
            alicePodTokenBalanceBefore - pTknAmt,
            "Incorrect Pod Token balance after adding leverage"
        );
        assertGt(IERC20(dai).balanceOf(address(this)), _adminDaiBalBefore, "Protocol fee successfully collected");
    }

    function _createSimplePod(address _underlying, address _pairedTkn) internal returns (address _newPod) {
        IDecentralizedIndex.Config memory _c;
        IDecentralizedIndex.Fees memory _f;
        _f.bond = 100;
        _f.debond = 100;
        address[] memory _t = new address[](1);
        _t[0] = _underlying;
        uint256[] memory _w = new uint256[](1);
        _w[0] = 100;
        _newPod = _createPod(
            "Test",
            "pTEST",
            _c,
            _f,
            _t,
            _w,
            address(0),
            false,
            abi.encode(
                _pairedTkn,
                address(peas),
                0x6B175474E89094C44Da98b954EedeAC495271d0F,
                0x7d544DD34ABbE24C8832db27820Ff53C151e949b,
                whitelister,
                0x024ff47D552cB222b265D68C7aeB26E586D5229D,
                dexAdapter
            )
        );
    }
}

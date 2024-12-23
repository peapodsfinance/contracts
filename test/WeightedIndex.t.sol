// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import {console2} from "forge-std/Test.sol";
import {PEAS} from "../contracts/PEAS.sol";
import {RewardsWhitelist} from "../contracts/RewardsWhitelist.sol";
import {V3TwapUtilities} from "../contracts/twaputils/V3TwapUtilities.sol";
import {UniswapDexAdapter} from "../contracts/dex/UniswapDexAdapter.sol";
import {IDecentralizedIndex} from "../contracts/interfaces/IDecentralizedIndex.sol";
import {IStakingPoolToken} from "../contracts/interfaces/IStakingPoolToken.sol";
import {WeightedIndex} from "../contracts/WeightedIndex.sol";
import {MockFlashMintRecipient} from "./mocks/MockFlashMintRecipient.sol";
import {PodHelperTest} from "./helpers/PodHelper.t.sol";
import "forge-std/console.sol";

contract WeightedIndexTest is PodHelperTest {
    PEAS public peas;
    RewardsWhitelist public rewardsWhitelist;
    V3TwapUtilities public twapUtils;
    UniswapDexAdapter public dexAdapter;
    WeightedIndex public pod;
    MockFlashMintRecipient public flashMintRecipient;

    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    uint256 public bondAmt = 1e18;
    uint16 fee = 100;
    uint256 public bondAmtAfterFee = bondAmt - (bondAmt * fee) / 10000;
    uint256 public feeAmtOnly1 = (bondAmt * fee) / 10000;
    uint256 public feeAmtOnly2 = (bondAmtAfterFee * fee) / 10000;

    // Test users
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public carol = address(0x3);

    event FlashMint(address indexed executor, address indexed recipient, uint256 amount);

    event AddLiquidity(address indexed user, uint256 idxLPTokens, uint256 pairedLPTokens);

    event RemoveLiquidity(address indexed user, uint256 lpTokens);

    function setUp() public override {
        super.setUp();
        peas = PEAS(0x02f92800F57BCD74066F5709F1Daa1A4302Df875);
        twapUtils = new V3TwapUtilities();
        rewardsWhitelist = new RewardsWhitelist();
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
                rewardsWhitelist,
                0x024ff47D552cB222b265D68C7aeB26E586D5229D,
                dexAdapter
            )
        );
        pod = WeightedIndex(payable(_pod));

        flashMintRecipient = new MockFlashMintRecipient();

        // Initial token setup for test users
        deal(address(peas), address(this), bondAmt * 100);
        deal(address(peas), alice, bondAmt * 100);
        deal(address(peas), bob, bondAmt * 100);
        deal(address(peas), carol, bondAmt * 100);
        deal(dai, address(this), 5 * 10e18);

        // Approve tokens for all test users
        vm.startPrank(alice);
        peas.approve(address(pod), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        peas.approve(address(pod), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(carol);
        peas.approve(address(pod), type(uint256).max);
        vm.stopPrank();
    }

    function test_bond() public {
        peas.approve(address(pod), peas.totalSupply());
        pod.bond(address(peas), bondAmt, 0);
        assertEq(pod.totalSupply(), bondAmt);
        assertEq(pod.balanceOf(address(this)), bondAmt);
    }

    function test_bondMultipleUsers() public {
        vm.startPrank(alice);
        pod.bond(address(peas), bondAmt, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        pod.bond(address(peas), bondAmt, 0);
        vm.stopPrank();

        assertEq(pod.totalSupply(), bondAmt * 2, "totalSupply not correct");
        assertEq(pod.balanceOf(alice), bondAmt, "alice incorrect");
        assertEq(pod.balanceOf(bob), bondAmtAfterFee, "bob incorrect");
    }

    function test_debond() public {
        uint256 _initPeasBal = peas.balanceOf(address(this));
        peas.approve(address(pod), peas.totalSupply());
        pod.bond(address(peas), bondAmt, 0);
        // uint256 initialBalance = peas.balanceOf(address(this));

        address[] memory _n1;
        uint8[] memory _n2;
        pod.debond(bondAmt, _n1, _n2);

        assertEq(pod.totalSupply(), 0, "totalSupply not correct");
        assertEq(pod.balanceOf(address(this)), 0, "pod bal");
        assertEq(peas.balanceOf(address(this)), _initPeasBal, "peas bal");
    }

    function test_debondMultipleUsers() public {
        vm.startPrank(alice);
        pod.bond(address(peas), bondAmt, 0);
        vm.stopPrank();

        vm.startPrank(bob);
        pod.bond(address(peas), bondAmt, 0);
        vm.stopPrank();

        uint256 aliceInitialBalance = peas.balanceOf(alice);
        uint256 bobInitialBalance = peas.balanceOf(bob);

        vm.startPrank(alice);
        address[] memory _n1;
        uint8[] memory _n2;
        pod.debond(bondAmt, _n1, _n2);
        vm.stopPrank();

        vm.startPrank(bob);
        pod.debond(bondAmtAfterFee, _n1, _n2);
        vm.stopPrank();

        assertEq(pod.totalSupply(), feeAmtOnly1 * 2 + feeAmtOnly2, "total supply");
        assertEq(pod.balanceOf(alice), 0, "pod alice bal now");
        assertEq(pod.balanceOf(bob), 0, "pod bob bal now");
        assertApproxEqAbs(
            peas.balanceOf(alice),
            aliceInitialBalance + bondAmt - (bondAmt * fee) / 10000,
            1, // 1 wei for rounding
            "peas alice bal now"
        );
        assertApproxEqAbs(
            peas.balanceOf(bob),
            bobInitialBalance + bondAmtAfterFee - (bondAmtAfterFee * fee) / 10000,
            1, // 1 wei for rounding
            "peas bob bal now"
        );
    }

    function test_transfer() public {
        peas.approve(address(pod), peas.totalSupply());
        pod.bond(address(peas), bondAmt, 0);

        uint256 transferAmount = bondAmtAfterFee / 2;
        pod.transfer(alice, transferAmount);

        assertEq(pod.balanceOf(address(this)), bondAmt - transferAmount);
        assertEq(pod.balanceOf(alice), transferAmount);
    }

    function test_transferFrom() public {
        peas.approve(address(pod), peas.totalSupply());
        pod.bond(address(peas), bondAmt, 0);

        uint256 transferAmount = bondAmt / 2;
        pod.approve(alice, transferAmount);

        vm.startPrank(alice);
        pod.transferFrom(address(this), bob, transferAmount);
        vm.stopPrank();

        assertEq(pod.balanceOf(address(this)), bondAmt - transferAmount, "this bal");
        assertEq(pod.balanceOf(bob), transferAmount, "bobs bal");
    }

    // Flash Mint Tests
    function test_flashMintBasic() public {
        uint256 mintAmount = 1000e18;
        uint256 expectedFee = mintAmount / 1000; // 0.1%

        deal(address(peas), address(this), expectedFee);
        peas.approve(address(pod), expectedFee);
        pod.bond(address(peas), expectedFee, 0);

        pod.flashMint(address(flashMintRecipient), mintAmount, "");

        assertEq(pod.totalSupply(), 0, "Total supply should be 0");
        assertEq(pod.balanceOf(address(flashMintRecipient)), 0, "Recipient should have no balance after flash mint");
    }

    function test_flashMintMinimumFee() public {
        uint256 mintAmount = 5; // Small amount where 0.1% would be 0
        uint256 expectedFee = 1; // 0.1%

        deal(address(peas), address(this), expectedFee);
        peas.approve(address(pod), expectedFee);
        pod.bond(address(peas), expectedFee, 0);

        pod.flashMint(address(flashMintRecipient), mintAmount, "");

        assertEq(pod.totalSupply(), 0, "Total supply should not increase");
        assertEq(pod.balanceOf(address(flashMintRecipient)), 0, "Recipient should have no balance after flash mint");
    }

    function test_flashMintCallback() public {
        bytes memory callbackData = "test data";
        uint256 mintAmount = 1000e18;
        uint256 expectedFee = mintAmount / 1000; // 0.1%

        deal(address(peas), address(this), expectedFee);
        peas.approve(address(pod), expectedFee);
        pod.bond(address(peas), expectedFee, 0);

        pod.flashMint(address(flashMintRecipient), mintAmount, callbackData);

        assertEq(flashMintRecipient.lastCallbackData(), callbackData, "Callback data should match");
    }

    function test_flashMintRevertOnCallbackFailure() public {
        flashMintRecipient.setRevertFlag(true);

        vm.expectRevert("MockFlashMintRecipient: forced revert");
        pod.flashMint(address(flashMintRecipient), 1000e18, "");
    }

    // function test_flashMintDuringBondDebond() public {
    //   // Initial bond
    //   peas.approve(address(pod), peas.totalSupply());
    //   pod.bond(address(peas), bondAmt, 0);
    //   uint256 supplyAfterBond = pod.totalSupply();

    //   // Flash mint
    //   uint256 mintAmount = 1000e18;
    //   uint256 expectedFee = mintAmount / 1000;

    //   deal(address(peas), address(this), expectedFee);
    //   peas.approve(address(pod), expectedFee);
    //   pod.bond(address(peas), expectedFee, 0);

    //   pod.flashMint(address(flashMintRecipient), mintAmount, '');
    //   uint256 supplyAfterFlashMint = pod.totalSupply();

    //   // Debond
    //   address[] memory _n1;
    //   uint8[] memory _n2;
    //   pod.debond(bondAmt, _n1, _n2);
    //   uint256 finalSupply = pod.totalSupply();

    //   assertEq(
    //     supplyAfterFlashMint,
    //     supplyAfterBond - expectedFee,
    //     'Supply after flash mint should include fee'
    //   );
    //   assertEq(
    //     finalSupply,
    //     0,
    //     'Final supply should only contain flash mint fee'
    //   );
    // }

    function test_flashMintLargeAmount() public {
        uint256 mintAmount = type(uint96).max; // Large amount
        uint256 expectedFee = mintAmount / 1000;

        deal(address(peas), address(this), expectedFee);
        peas.approve(address(pod), expectedFee);
        pod.bond(address(peas), expectedFee, 0);

        pod.flashMint(address(flashMintRecipient), mintAmount, "");

        assertEq(pod.totalSupply(), 0, "Total supply should not increase");
    }

    function test_convertToAssets_ZeroSupply() public view {
        // When totalSupply is 0, convertToAssets should return the input amount
        // as there's a 1:1 ratio when no shares exist
        uint256 shares = 1e18;
        uint256 assets = pod.convertToAssets(shares);
        assertEq(assets, shares - ((shares * fee) / 10000), "Should return same amount when supply is 0");
    }

    function test_convertToAssets_OneToOneRatio() public {
        // First bond to create initial supply with 1:1 ratio (minus fees)
        peas.approve(address(pod), bondAmt);
        pod.bond(address(peas), bondAmt, 0);

        // Calculate expected assets (should be same as shares since ratio is 1:1)
        uint256 shares = 1e18;
        uint256 assets = pod.convertToAssets(shares);
        assertEq(assets, shares - ((shares * fee) / 10000), "Should maintain 1:1 ratio");
    }

    function test_convertToAssets_DifferentRatio() public {
        // First bond to create initial supply
        peas.approve(address(pod), bondAmt);
        pod.bond(address(peas), bondAmt, 0);

        // Create asset value increase by bonding and burning shares
        peas.approve(address(pod), bondAmt);
        pod.bond(address(peas), bondAmt, 0);
        pod.burn(bondAmt);

        // Now 1 share should be worth 2 assets
        uint256 shares = 1e18;
        uint256 assets = pod.convertToAssets(shares);
        assertEq(assets, shares * 2 - ((shares * 2 * fee) / 10000), "Should reflect 2:1 asset to share ratio");
    }

    function test_convertToShares_ZeroSupply() public view {
        // When totalSupply is 0, convertToShares should return the input amount
        // as there's a 1:1 ratio when no shares exist
        uint256 assets = 1e18;
        uint256 shares = pod.convertToShares(assets);
        assertEq(shares, assets - ((assets * fee) / 10000), "Should return same amount when supply is 0");
    }

    function test_convertToShares_OneToOneRatio() public {
        // First bond to create initial supply with 1:1 ratio (minus fees)
        peas.approve(address(pod), bondAmt);
        pod.bond(address(peas), bondAmt, 0);

        // Calculate expected shares (should be same as assets since ratio is 1:1)
        uint256 assets = 1e18;
        uint256 shares = pod.convertToShares(assets);
        assertEq(shares, assets - ((assets * fee) / 10000), "Should maintain 1:1 ratio");
    }

    function test_convertToShares_DifferentRatio() public {
        // First bond to create initial supply
        peas.approve(address(pod), bondAmt);
        pod.bond(address(peas), bondAmt, 0);

        // Create asset value increase by bonding and burning shares
        peas.approve(address(pod), bondAmt);
        pod.bond(address(peas), bondAmt, 0);
        pod.burn(bondAmt);

        // Now 2 assets should be worth 1 share (inverse of convertToAssets ratio)
        uint256 assets = 2e18;
        uint256 shares = pod.convertToShares(assets);
        assertEq(shares, assets / 2 - (((assets / 2) * fee) / 10000), "Should reflect 1:2 share to asset ratio");
    }

    function test_addLiquidityV2() public {
        // First bond some tokens to have pTKN to add liquidity with
        uint256 podTokensToAdd = 1e18;
        uint256 pairedTokensToAdd = 1e18;
        uint256 slippage = 50; // 5% slippage

        // Bond tokens first to have some to add liquidity with
        peas.approve(address(pod), podTokensToAdd * 2);
        pod.bond(address(peas), podTokensToAdd, 0);

        // Deal some paired tokens to this contract
        deal(pod.PAIRED_LP_TOKEN(), address(this), pairedTokensToAdd);

        // Get initial balances
        uint256 initialPodBalance = pod.balanceOf(address(this));
        uint256 initialPairedBalance = IERC20(pod.PAIRED_LP_TOKEN()).balanceOf(address(this));

        // Approve tokens for liquidity addition
        IERC20(pod.PAIRED_LP_TOKEN()).approve(address(pod), pairedTokensToAdd);

        // Get initial LP token balance
        address v2Pool = pod.DEX_HANDLER().getV2Pool(address(pod), pod.PAIRED_LP_TOKEN());
        uint256 initialLpBalance = IERC20(v2Pool).balanceOf(address(this));

        // Expect AddLiquidity event
        vm.expectEmit(true, false, false, true);
        emit AddLiquidity(address(this), podTokensToAdd, pairedTokensToAdd);

        // Add liquidity
        uint256 lpTokensReceived = pod.addLiquidityV2(podTokensToAdd, pairedTokensToAdd, slippage, block.timestamp);

        // Verify LP tokens were received
        assertGt(lpTokensReceived, 0, "Should receive LP tokens");
        assertEq(
            IERC20(v2Pool).balanceOf(address(this)) - initialLpBalance,
            lpTokensReceived,
            "LP token balance should increase by returned amount"
        );

        // Verify token balances were reduced
        assertEq(pod.balanceOf(address(this)), initialPodBalance - podTokensToAdd, "Pod token balance should decrease");
        assertEq(
            IERC20(pod.PAIRED_LP_TOKEN()).balanceOf(address(this)),
            initialPairedBalance - pairedTokensToAdd,
            "Paired token balance should decrease"
        );
    }

    function test_removeLiquidityV2() public {
        // First add liquidity so we have LP tokens to remove
        uint256 podTokensToAdd = 1e18;
        uint256 pairedTokensToAdd = 1e18;
        uint256 slippage = 50; // 5% slippage

        // Bond tokens first to have some to add liquidity with
        peas.approve(address(pod), podTokensToAdd * 2);
        pod.bond(address(peas), podTokensToAdd, 0);

        // Deal some paired tokens and approve for liquidity addition
        deal(pod.PAIRED_LP_TOKEN(), address(this), pairedTokensToAdd);
        IERC20(pod.PAIRED_LP_TOKEN()).approve(address(pod), pairedTokensToAdd);

        // Add liquidity first
        uint256 lpTokensReceived = pod.addLiquidityV2(podTokensToAdd, pairedTokensToAdd, slippage, block.timestamp);

        // Get initial balances before removal
        uint256 initialPodBalance = pod.balanceOf(address(this));
        uint256 initialPairedBalance = IERC20(pod.PAIRED_LP_TOKEN()).balanceOf(address(this));

        // Get V2 pool address
        address v2Pool = pod.DEX_HANDLER().getV2Pool(address(pod), pod.PAIRED_LP_TOKEN());

        // Approve LP tokens for removal
        IERC20(v2Pool).approve(address(pod), lpTokensReceived);

        // Expect RemoveLiquidity event
        vm.expectEmit(true, false, false, true);
        emit RemoveLiquidity(address(this), lpTokensReceived);

        // Remove liquidity
        pod.removeLiquidityV2(
            lpTokensReceived,
            0, // min pod tokens (accepting any slippage for test)
            0, // min paired tokens (accepting any slippage for test)
            block.timestamp
        );

        // Verify LP tokens were burned
        assertEq(IERC20(v2Pool).balanceOf(address(this)), 0, "All LP tokens should be burned");

        // Verify token balances increased
        assertGt(pod.balanceOf(address(this)), initialPodBalance, "Pod token balance should increase");
        assertGt(
            IERC20(pod.PAIRED_LP_TOKEN()).balanceOf(address(this)),
            initialPairedBalance,
            "Paired token balance should increase"
        );
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/PodUnwrapLocker.sol";
import "./mocks/TestERC20.sol";
import {WeightedIndex} from "../contracts/WeightedIndex.sol";
import {MockOwnable} from "./mocks/MockOwnable.sol";
import {PodHelperTest} from "./helpers/PodHelper.t.sol";

interface IStakingPoolToken_OLD {
    function indexFund() external view returns (address);
}

contract PodUnwrapLockerTest is PodHelperTest {
    address constant peas = 0x02f92800F57BCD74066F5709F1Daa1A4302Df875;
    address constant dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    PodUnwrapLocker public locker;
    WeightedIndex public pod;
    TestERC20 public token1;
    TestERC20 public token2;
    address public user = address(0x1);
    address public feeRecipient = address(0x2);
    MockOwnable public feeRecipOwnable;
    uint256 public constant POD_COOLDOWN = 7 days;
    uint16 public constant DEBOND_FEE = 500; // 5% debond fee

    function setUp() public override {
        super.setUp();

        // Deploy test tokens
        token1 = new TestERC20("Token1", "TK1");
        token2 = new TestERC20("Token2", "TK2");

        feeRecipOwnable = new MockOwnable(feeRecipient);

        // Setup pod
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        uint256[] memory weights = new uint256[](2);
        weights[0] = 50;
        weights[1] = 50;
        // Get a pod to test with
        address podToDup = IStakingPoolToken_OLD(0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1).indexFund(); // spPDAI
        (, address _pod) = _duplicatePod(podToDup, dai, tokens, weights);
        pod = WeightedIndex(payable(_pod));

        // Mock pod's config for cooldown
        vm.mockCall(
            address(pod),
            abi.encodeWithSelector(IDecentralizedIndex.config.selector),
            abi.encode(
                IDecentralizedIndex.Config({
                    partner: address(0),
                    debondCooldown: POD_COOLDOWN,
                    hasTransferTax: false,
                    blacklistTKNpTKNPoolV2: false
                })
            )
        );

        // Mock pod's fees for early withdrawal with DEBOND_FEE for testing
        IDecentralizedIndex.Fees memory _fees = pod.fees();
        vm.mockCall(
            address(pod),
            abi.encodeWithSelector(IDecentralizedIndex.fees.selector),
            abi.encode(
                IDecentralizedIndex.Fees({
                    burn: _fees.burn,
                    bond: _fees.bond,
                    debond: DEBOND_FEE,
                    buy: _fees.buy,
                    sell: _fees.sell,
                    partner: _fees.partner
                })
            )
        );

        // Deploy locker with fee recipient
        locker = new PodUnwrapLocker(address(feeRecipOwnable));

        // Send tokens to user
        token1.transfer(user, 1000e18);
        token2.transfer(user, 1000e18);

        vm.startPrank(user);
        token1.approve(address(pod), type(uint256).max);
        token2.approve(address(pod), type(uint256).max);
        vm.stopPrank();
    }

    function testDebondAndLock() public {
        uint256 podAmount = 100e18;

        vm.startPrank(user);
        // Bond tokens to pod first
        pod.bond(address(token1), podAmount, 0);

        // Approve and debond through locker
        IERC20(address(pod)).approve(address(locker), podAmount);
        locker.debondAndLock(address(pod), podAmount);
        vm.stopPrank();

        // Check lock was created
        (
            address lockUser,
            address lockPod,
            address[] memory tokens,
            uint256[] memory amounts,
            uint256 unlockTime,
            bool withdrawn
        ) = locker.getLockInfo(0);

        assertEq(lockUser, user);
        assertEq(lockPod, address(pod));
        assertEq(tokens.length, 2);
        assertEq(tokens[0], address(token1));
        assertEq(tokens[1], address(token2));
        assertTrue(amounts[0] > 0);
        assertTrue(amounts[1] > 0);
        assertEq(unlockTime, block.timestamp + POD_COOLDOWN);
        assertFalse(withdrawn);
    }

    function testWithdrawBeforeLockExpiry() public {
        uint256 podAmount = 100e18;

        vm.startPrank(user);
        // Bond tokens to pod first
        pod.bond(address(token1), podAmount, 0);

        // Approve and debond through locker
        IERC20(address(pod)).approve(address(locker), podAmount);
        locker.debondAndLock(address(pod), podAmount);

        // Try to withdraw before lock expiry
        vm.expectRevert();
        locker.withdraw(0);
        vm.stopPrank();
    }

    function testWithdrawAfterLockExpiry() public {
        uint256 podAmount = 100e18;

        vm.startPrank(user);
        // Bond tokens to pod first
        pod.bond(address(token1), podAmount, 0);

        // Approve and debond through locker
        IERC20(address(pod)).approve(address(locker), podAmount);
        locker.debondAndLock(address(pod), podAmount);

        // Move time forward past lock duration
        vm.warp(block.timestamp + POD_COOLDOWN + 1);

        // Get balances before withdrawal
        uint256 token1BalanceBefore = token1.balanceOf(user);
        uint256 token2BalanceBefore = token2.balanceOf(user);

        // Withdraw
        locker.withdraw(0);
        vm.stopPrank();

        // Verify tokens were received
        assertTrue(token1.balanceOf(user) > token1BalanceBefore);
        assertTrue(token2.balanceOf(user) > token2BalanceBefore);

        // Verify lock is marked as withdrawn
        (,,,,, bool withdrawn) = locker.getLockInfo(0);
        assertTrue(withdrawn);
    }

    function testCannotWithdrawTwice() public {
        uint256 podAmount = 100e18;

        vm.startPrank(user);
        // Bond tokens to pod first
        pod.bond(address(token1), podAmount, 0);

        // Approve and debond through locker
        IERC20(address(pod)).approve(address(locker), podAmount);
        locker.debondAndLock(address(pod), podAmount);

        // Move time forward past lock duration
        vm.warp(block.timestamp + POD_COOLDOWN + 1);

        // First withdrawal should succeed
        locker.withdraw(0);

        // Second withdrawal should fail
        vm.expectRevert();
        locker.withdraw(0);
        vm.stopPrank();
    }

    function testEarlyWithdrawBeforeLockExpiry() public {
        uint256 podAmount = 100e18;

        vm.startPrank(user);
        // Bond tokens to pod first
        pod.bond(address(token1), podAmount, 0);

        // Approve and debond through locker
        IERC20(address(pod)).approve(address(locker), podAmount);
        locker.debondAndLock(address(pod), podAmount);

        // Get lock info and balances before early withdrawal
        (,,, uint256[] memory amounts,,) = locker.getLockInfo(0);
        uint256 token1BalanceBefore = token1.balanceOf(user);
        uint256 token2BalanceBefore = token2.balanceOf(user);
        uint256 feeRecipientToken1Before = token1.balanceOf(feeRecipient);
        uint256 feeRecipientToken2Before = token2.balanceOf(feeRecipient);

        // Early withdraw
        locker.earlyWithdraw(0);
        vm.stopPrank();

        // Calculate expected amounts after penalty (debondFee + 10% * debondFee)
        uint256 totalPenalty = DEBOND_FEE + DEBOND_FEE / 10; // 5% + 10%*5%
        uint256 expectedToken1 = (amounts[0] * (10000 - totalPenalty)) / 10000;
        uint256 expectedToken2 = (amounts[1] * (10000 - totalPenalty)) / 10000;
        uint256 expectedFeeToken1 = (amounts[0] * totalPenalty) / 10000;
        uint256 expectedFeeToken2 = (amounts[1] * totalPenalty) / 10000;

        // Verify received amounts match expected amounts after penalty
        assertEq(token1.balanceOf(user) - token1BalanceBefore, expectedToken1, "User token1 amount incorrect");
        assertEq(token2.balanceOf(user) - token2BalanceBefore, expectedToken2, "User token2 amount incorrect");

        // Verify fee recipient received correct penalty amounts
        assertEq(
            token1.balanceOf(feeRecipient) - feeRecipientToken1Before,
            expectedFeeToken1,
            "Fee recipient token1 amount incorrect"
        );
        assertEq(
            token2.balanceOf(feeRecipient) - feeRecipientToken2Before,
            expectedFeeToken2,
            "Fee recipient token2 amount incorrect"
        );

        // Verify lock is marked as withdrawn
        (,,,,, bool withdrawn) = locker.getLockInfo(0);
        assertTrue(withdrawn);
    }

    function testEarlyWithdrawAfterLockExpiry() public {
        uint256 podAmount = 100e18;

        vm.startPrank(user);
        // Bond tokens to pod first
        pod.bond(address(token1), podAmount, 0);

        // Approve and debond through locker
        IERC20(address(pod)).approve(address(locker), podAmount);
        locker.debondAndLock(address(pod), podAmount);

        // Move time forward past lock duration
        vm.warp(block.timestamp + POD_COOLDOWN + 1);

        // Get lock info and balances before withdrawal
        (,,, uint256[] memory amounts,,) = locker.getLockInfo(0);
        uint256 token1BalanceBefore = token1.balanceOf(user);
        uint256 token2BalanceBefore = token2.balanceOf(user);
        uint256 feeRecipientToken1Before = token1.balanceOf(feeRecipient);
        uint256 feeRecipientToken2Before = token2.balanceOf(feeRecipient);

        // Early withdraw after lock expiry (should not apply penalty)
        locker.earlyWithdraw(0);
        vm.stopPrank();

        // Verify received full amounts with no penalty
        assertEq(token1.balanceOf(user) - token1BalanceBefore, amounts[0], "User token1 amount incorrect");
        assertEq(token2.balanceOf(user) - token2BalanceBefore, amounts[1], "User token2 amount incorrect");

        // Verify fee recipient received nothing
        assertEq(
            token1.balanceOf(feeRecipient) - feeRecipientToken1Before, 0, "Fee recipient token1 amount should be 0"
        );
        assertEq(
            token2.balanceOf(feeRecipient) - feeRecipientToken2Before, 0, "Fee recipient token2 amount should be 0"
        );

        // Verify lock is marked as withdrawn
        (,,,,, bool withdrawn) = locker.getLockInfo(0);
        assertTrue(withdrawn);
    }

    function testCannotEarlyWithdrawTwice() public {
        uint256 podAmount = 100e18;

        vm.startPrank(user);
        // Bond tokens to pod first
        pod.bond(address(token1), podAmount, 0);

        // Approve and debond through locker
        IERC20(address(pod)).approve(address(locker), podAmount);
        locker.debondAndLock(address(pod), podAmount);

        // First early withdrawal should succeed
        locker.earlyWithdraw(0);

        // Second early withdrawal should fail
        vm.expectRevert();
        locker.earlyWithdraw(0);
        vm.stopPrank();
    }
}

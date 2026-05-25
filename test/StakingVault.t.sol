// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {StakingVault} from "../contracts/utils/StakingVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockFeeOnTransferERC20} from "./mocks/MockFeeOnTransferERC20.sol";
import {MockReentrantERC20, IStakingVaultReentry} from "./mocks/MockReentrantERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract StakingVaultTest is Test {
    StakingVault public vault;
    MockERC20 public asset;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    /// @dev `_decimalsOffset() = 6` → 1 asset unit corresponds to SCALE shares.
    uint256 internal constant SCALE = 10 ** 6;

    // Events
    event DepositorWhitelisted(address indexed depositor, uint256 cap, uint256 currentPrincipal);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event Paused(address account);
    event Unpaused(address account);

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        asset = new MockERC20("Test Token", "TEST");
        vault = new StakingVault(IERC20(address(asset)), "Test Vault", "vTEST");
        // Ownable2Step: must transfer AND accept
        vault.transferOwnership(owner);
        vm.prank(owner);
        vault.acceptOwnership();

        asset.mint(user1, 10000e18);
        asset.mint(user2, 10000e18);
        asset.mint(user3, 10000e18);

        vm.prank(user1);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(user3);
        asset.approve(address(vault), type(uint256).max);
    }

    function _whitelistOne(address user, uint256 cap) internal {
        address[] memory addrs = new address[](1);
        addrs[0] = user;
        uint256[] memory caps = new uint256[](1);
        caps[0] = cap;
        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(addrs, caps);
    }

    // ============ Constructor ============

    function test_constructor() public view {
        assertEq(address(vault.asset()), address(asset));
        assertEq(vault.name(), "Test Vault");
        assertEq(vault.symbol(), "vTEST");
        assertEq(vault.owner(), owner);
    }

    function test_decimalsOffset_isSix() public view {
        // vault.decimals() = asset.decimals() (18) + offset (6) = 24
        assertEq(vault.decimals(), 24);
    }

    function test_RevertWhen_ConstructorZeroAsset() public {
        vm.expectRevert(StakingVault.StakingVault__ZeroAsset.selector);
        new StakingVault(IERC20(address(0)), "Bad", "BAD");
    }

    // ============ Whitelist / setDepositorsWhitelistDepositAmounts ============

    function test_setDepositorsWhitelistDepositAmounts_single() public {
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory caps = new uint256[](1);
        caps[0] = 1000e18;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit DepositorWhitelisted(user1, 1000e18, 0);
        vault.setDepositorsWhitelistDepositAmounts(depositors, caps);

        assertEq(vault.depositCap(user1), 1000e18);
        assertEq(vault.depositedPrincipal(user1), 0);
        assertEq(vault.maxDeposit(user1), 1000e18);
    }

    function test_setDepositorsWhitelistDepositAmounts_multiple() public {
        address[] memory depositors = new address[](3);
        depositors[0] = user1;
        depositors[1] = user2;
        depositors[2] = user3;
        uint256[] memory caps = new uint256[](3);
        caps[0] = 1000e18;
        caps[1] = 2000e18;
        caps[2] = 3000e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, caps);

        assertEq(vault.depositCap(user1), 1000e18);
        assertEq(vault.depositCap(user2), 2000e18);
        assertEq(vault.depositCap(user3), 3000e18);
    }

    function test_setDepositorsWhitelistDepositAmounts_canUpdate() public {
        _whitelistOne(user1, 1000e18);
        assertEq(vault.depositCap(user1), 1000e18);
        _whitelistOne(user1, 2000e18);
        assertEq(vault.depositCap(user1), 2000e18);
    }

    function test_RevertWhen_NonOwnerSetsWhitelist() public {
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory caps = new uint256[](1);
        caps[0] = 1000e18;

        vm.prank(user1);
        vm.expectRevert();
        vault.setDepositorsWhitelistDepositAmounts(depositors, caps);
    }

    function test_RevertWhen_ArrayLengthMismatch() public {
        address[] memory depositors = new address[](2);
        depositors[0] = user1;
        depositors[1] = user2;
        uint256[] memory caps = new uint256[](1);
        caps[0] = 1000e18;

        vm.prank(owner);
        vm.expectRevert(StakingVault.StakingVault__ArrayLengthMismatch.selector);
        vault.setDepositorsWhitelistDepositAmounts(depositors, caps);
    }

    function test_RevertWhen_SetCapForZeroAddress() public {
        address[] memory depositors = new address[](1);
        depositors[0] = address(0);
        uint256[] memory caps = new uint256[](1);
        caps[0] = 1000e18;

        vm.prank(owner);
        vm.expectRevert(StakingVault.StakingVault__ZeroAddress.selector);
        vault.setDepositorsWhitelistDepositAmounts(depositors, caps);
    }

    // ============ Deposit ============

    function test_deposit() public {
        _whitelistOne(user1, 1000e18);
        uint256 depositAmount = 100e18;

        vm.prank(user1);
        uint256 shares = vault.deposit(depositAmount, user1);

        assertEq(shares, depositAmount * SCALE);
        assertEq(vault.balanceOf(user1), depositAmount * SCALE);
        assertEq(asset.balanceOf(address(vault)), depositAmount);
        assertEq(vault.depositedPrincipal(user1), depositAmount);
        assertEq(vault.maxDeposit(user1), 900e18);
    }

    function test_RevertWhen_DepositReceiverMismatch() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(StakingVault.StakingVault__ReceiverMismatch.selector, user1, user2)
        );
        vault.deposit(100e18, user2);
    }

    function test_deposit_multipleDeposits() public {
        _whitelistOne(user1, 1000e18);

        vm.prank(user1);
        vault.deposit(300e18, user1);
        assertEq(vault.depositedPrincipal(user1), 300e18);
        assertEq(vault.maxDeposit(user1), 700e18);

        vm.prank(user1);
        vault.deposit(200e18, user1);
        assertEq(vault.depositedPrincipal(user1), 500e18);
        assertEq(vault.maxDeposit(user1), 500e18);

        assertEq(vault.balanceOf(user1), 500e18 * SCALE);
    }

    function test_deposit_exactlyMaxDeposit_succeeds() public {
        _whitelistOne(user1, 1000e18);
        uint256 cap = vault.maxDeposit(user1);
        vm.prank(user1);
        uint256 shares = vault.deposit(cap, user1);
        assertEq(shares, cap * SCALE);
        assertEq(vault.depositedPrincipal(user1), cap);
        assertEq(vault.maxDeposit(user1), 0);
    }

    /// @dev F-5 (code-review): super.mint internally checks `shares > maxMint(receiver)`. With
    ///      our override `maxMint = previewDeposit(maxDeposit)`, the boundary case
    ///      `mint(maxMint(user), user)` must NOT spuriously revert — locks in the floor/ceil
    ///      round-trip safety proof from the contract NatSpec.
    function test_mint_exactlyMaxMint_succeeds() public {
        _whitelistOne(user1, 1000e18);
        uint256 maxShares = vault.maxMint(user1);
        assertGt(maxShares, 0);
        vm.prank(user1);
        uint256 assets = vault.mint(maxShares, user1);
        assertGt(assets, 0);
        // After consuming all of maxMint, no room left
        assertEq(vault.maxMint(user1), 0);
        assertEq(vault.maxDeposit(user1), 0);
    }

    function test_RevertWhen_DepositExceedsCap() public {
        _whitelistOne(user1, 50e18);
        vm.prank(user1);
        // OZ ERC4626 reverts with ERC4626ExceededMaxDeposit via super's check
        vm.expectRevert();
        vault.deposit(100e18, user1);
    }

    function test_RevertWhen_DepositWithoutWhitelist() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.deposit(100e18, user1);
    }

    // ============ Mint ============

    function test_mint() public {
        _whitelistOne(user1, 1000e18);
        uint256 sharesToMint = 100e18 * SCALE; // 100 assets worth of shares
        vm.prank(user1);
        uint256 assets = vault.mint(sharesToMint, user1);

        assertEq(assets, 100e18);
        assertEq(vault.balanceOf(user1), sharesToMint);
        assertEq(vault.depositedPrincipal(user1), 100e18);
        assertEq(vault.maxDeposit(user1), 900e18);
    }

    function test_RevertWhen_MintReceiverMismatch() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(StakingVault.StakingVault__ReceiverMismatch.selector, user1, user2)
        );
        vault.mint(100e18 * SCALE, user2);
    }

    // ============ Redeem ============

    function test_redeem() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(1000e18, user1);
        assertEq(vault.maxDeposit(user1), 0);

        uint256 sharesToRedeem = 500e18 * SCALE;
        vm.prank(user1);
        uint256 assets = vault.redeem(sharesToRedeem, user1, user1);

        assertEq(assets, 500e18);
        assertEq(vault.balanceOf(user1), 500e18 * SCALE);
        assertEq(vault.depositedPrincipal(user1), 500e18);
        assertEq(vault.maxDeposit(user1), 500e18);
        assertEq(asset.balanceOf(user1), 9500e18);
    }

    function test_redeem_full() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(1000e18, user1);

        vm.prank(user1);
        uint256 assets = vault.redeem(1000e18 * SCALE, user1, user1);

        assertEq(assets, 1000e18);
        assertEq(vault.balanceOf(user1), 0);
        assertEq(vault.depositedPrincipal(user1), 0);
        assertEq(vault.maxDeposit(user1), 1000e18);
        assertEq(asset.balanceOf(user1), 10000e18);
    }

    function test_redeem_restoresPrincipal_proportional() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(1000e18, user1);

        // Redeem a third of shares: principalOut = 1000 * (shares/3) / shares = ~333
        uint256 third = (1000e18 * SCALE) / 3;
        vm.prank(user1);
        vault.redeem(third, user1, user1);

        // 1000 * third / (1000e18 * SCALE) = floor → expect ≈ 333.33e18, floored
        uint256 expectedPrincipal = 1000e18 - (1000e18 * third) / (1000e18 * SCALE);
        assertEq(vault.depositedPrincipal(user1), expectedPrincipal);
    }

    function test_redeem_withAllowance() public {
        // user1 deposits, user2 redeems via allowance to user3
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(1000e18, user1);

        vm.prank(user1);
        vault.approve(user2, 500e18 * SCALE);

        vm.prank(user2);
        uint256 assets = vault.redeem(500e18 * SCALE, user3, user1);

        assertEq(assets, 500e18);
        assertEq(vault.balanceOf(user1), 500e18 * SCALE);
        // Principal credit goes to user1 (the share owner), not user2 (the caller)
        assertEq(vault.depositedPrincipal(user1), 500e18);
        // user2 (caller) did not consume any of their own cap
        assertEq(vault.depositedPrincipal(user2), 0);
        // user3 (receiver) gets the assets
        assertEq(asset.balanceOf(user3), 10500e18);
    }

    // ============ Withdraw ============

    function test_withdraw() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(1000e18, user1);

        vm.prank(user1);
        uint256 shares = vault.withdraw(500e18, user1, user1);

        assertEq(shares, 500e18 * SCALE);
        assertEq(vault.balanceOf(user1), 500e18 * SCALE);
        assertEq(vault.depositedPrincipal(user1), 500e18);
        assertEq(vault.maxDeposit(user1), 500e18);
        // CRITICAL: withdraw returns EXACTLY the requested assets (audit F-3 fix)
        assertEq(asset.balanceOf(user1), 9500e18);
    }

    function test_RevertWhen_WithdrawExceedsBalance() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(500e18, user1);

        vm.prank(user1);
        vm.expectRevert();
        vault.withdraw(600e18, user1, user1);
    }

    // ============ F-1 regression: cap does not grow after yield ============

    function test_cap_doesNotGrow_afterYield_fullRedeem() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(1000e18, user1);

        // Team reimburses by direct transfer
        asset.mint(address(vault), 500e18);
        assertEq(vault.totalAssets(), 1500e18);

        // User1 redeems all shares
        uint256 balance = vault.balanceOf(user1);
        vm.prank(user1);
        uint256 assets = vault.redeem(balance, user1, user1);

        // User receives more assets than originally deposited (yield delivered)
        assertGt(assets, 1000e18);
        assertApproxEqAbs(assets, 1500e18, 1e12); // dust from virtual shares offset

        // CRITICAL: principal fully restored to 0; cap NOT inflated
        assertEq(vault.depositedPrincipal(user1), 0);
        assertEq(vault.maxDeposit(user1), 1000e18); // exact original cap, not 1500
    }

    function test_cap_doesNotGrow_afterYield_partialRedeem() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(1000e18, user1);

        asset.mint(address(vault), 500e18);

        uint256 balance = vault.balanceOf(user1);
        uint256 half = balance / 2;
        vm.prank(user1);
        uint256 assets = vault.redeem(half, user1, user1);

        // User receives ~750 assets (half of 1500 totalAssets at share price 1.5)
        assertGt(assets, 500e18);
        // Principal halved (proportional to shares burned)
        assertEq(vault.depositedPrincipal(user1), 500e18);
        // maxDeposit allows depositing 500 more — total cap consumption stays 1000
        assertEq(vault.maxDeposit(user1), 500e18);
    }

    function test_cap_doesNotGrow_afterYield_multiplePartials() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(1000e18, user1);
        asset.mint(address(vault), 500e18);

        uint256 balance = vault.balanceOf(user1);
        // Redeem in thirds (approximately)
        uint256 third = balance / 3;
        vm.prank(user1);
        vault.redeem(third, user1, user1);
        vm.prank(user1);
        vault.redeem(third, user1, user1);
        // Final: redeem remaining balance to force exact-zero principal
        uint256 remaining = vault.balanceOf(user1);
        vm.prank(user1);
        vault.redeem(remaining, user1, user1);

        // After full redemption via partials: principal exactly 0, cap fully restored
        assertEq(vault.depositedPrincipal(user1), 0);
        assertEq(vault.maxDeposit(user1), 1000e18);
    }

    /// @dev F-6 (code-review): Post-yield, tiny redeems whose principalOut floors to 0 leave
    ///      principal "stuck" above 0 (dust). A subsequent full-balance redeem resets it.
    ///      Documents the acceptable QoS noted in `redeem`'s NatSpec — and guards against a
    ///      future change that breaks the reset-on-full-redeem property.
    function test_dustAccumulation_resolvedByFullRedeem() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(1000e18, user1);
        // Yield → share price > 1
        asset.mint(address(vault), 500e18);

        uint256 dustIterations = 50;
        uint256 dustShares = 1; // 1 wei of share, far below the principal-flooring threshold

        for (uint256 i = 0; i < dustIterations; i++) {
            vm.prank(user1);
            vault.redeem(dustShares, user1, user1);
        }

        // Principal is stuck at 1000 because each tiny redeem floored principalOut to 0
        assertEq(vault.depositedPrincipal(user1), 1000e18);
        // Balance has dropped by the dust burns
        assertEq(vault.balanceOf(user1), 1000e18 * SCALE - dustIterations);

        // Full-balance redeem resets principal cleanly
        uint256 remaining = vault.balanceOf(user1);
        vm.prank(user1);
        vault.redeem(remaining, user1, user1);
        assertEq(vault.depositedPrincipal(user1), 0);
        assertEq(vault.maxDeposit(user1), 1000e18);
    }

    function test_redeem_redeposit_neverExceedsCap() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(1000e18, user1);
        asset.mint(address(vault), 500e18);

        uint256 balance = vault.balanceOf(user1);
        vm.prank(user1);
        vault.redeem(balance / 2, user1, user1);
        assertEq(vault.depositedPrincipal(user1), 500e18);

        // Re-deposit the freed cap
        vm.prank(user1);
        vault.deposit(500e18, user1);
        assertEq(vault.depositedPrincipal(user1), 1000e18);
        assertLe(vault.depositedPrincipal(user1), vault.depositCap(user1));
    }

    function test_maxDeposit_saturatesAtZero_whenCapLoweredBelowPrincipal() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(800e18, user1);

        // Owner lowers cap below current principal
        _whitelistOne(user1, 500e18);

        assertEq(vault.depositedPrincipal(user1), 800e18); // unchanged
        assertEq(vault.depositCap(user1), 500e18);
        assertEq(vault.maxDeposit(user1), 0); // saturates
    }

    // ============ Soulbound shares ============

    function test_RevertWhen_ShareTransfer() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(1000e18, user1);

        vm.prank(user1);
        vm.expectRevert(StakingVault.StakingVault__NonTransferable.selector);
        vault.transfer(user2, 100);
    }

    function test_RevertWhen_ShareTransferFrom() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(1000e18, user1);

        vm.prank(user1);
        vault.approve(user2, 100);

        vm.prank(user2);
        vm.expectRevert(StakingVault.StakingVault__NonTransferable.selector);
        vault.transferFrom(user1, user3, 100);
    }

    function test_approve_emitsEvent_but_transferFrom_reverts() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(1000e18, user1);

        vm.prank(user1);
        vault.approve(user2, 100);
        assertEq(vault.allowance(user1, user2), 100);

        // transferFrom reverts even though allowance is set
        vm.prank(user2);
        vm.expectRevert(StakingVault.StakingVault__NonTransferable.selector);
        vault.transferFrom(user1, user3, 50);
    }

    // ============ Pausable ============

    function test_pause_blocksDeposit() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(owner);
        vault.pause();

        vm.prank(user1);
        vm.expectRevert(); // OZ EnforcedPause
        vault.deposit(100e18, user1);
    }

    function test_pause_blocksMint() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(owner);
        vault.pause();

        vm.prank(user1);
        vm.expectRevert();
        vault.mint(100e18 * SCALE, user1);
    }

    function test_pause_allowsRedeem() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(1000e18, user1);

        vm.prank(owner);
        vault.pause();

        // Redeem succeeds even while paused
        vm.prank(user1);
        uint256 assets = vault.redeem(500e18 * SCALE, user1, user1);
        assertEq(assets, 500e18);
    }

    function test_pause_allowsWithdraw() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vault.deposit(1000e18, user1);

        vm.prank(owner);
        vault.pause();

        vm.prank(user1);
        uint256 shares = vault.withdraw(500e18, user1, user1);
        assertEq(shares, 500e18 * SCALE);
    }

    function test_pauseAndUnpause_cycleAllowsDepositAgain() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(owner);
        vault.pause();
        vm.prank(owner);
        vault.unpause();

        vm.prank(user1);
        uint256 shares = vault.deposit(100e18, user1);
        assertEq(shares, 100e18 * SCALE);
    }

    function test_RevertWhen_NonOwnerPauses() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.pause();
    }

    function test_maxDeposit_returnsZero_whenPaused() public {
        _whitelistOne(user1, 1000e18);
        assertEq(vault.maxDeposit(user1), 1000e18);

        vm.prank(owner);
        vault.pause();
        assertEq(vault.maxDeposit(user1), 0);
    }

    function test_maxMint_returnsZero_whenPaused() public {
        _whitelistOne(user1, 1000e18);
        assertGt(vault.maxMint(user1), 0);

        vm.prank(owner);
        vault.pause();
        assertEq(vault.maxMint(user1), 0);
    }

    // ============ Ownable2Step ============

    function test_Ownable2Step_pendingOwnerBeforeAccept() public {
        // Start a fresh vault to test the pre-accept state directly
        StakingVault freshVault = new StakingVault(IERC20(address(asset)), "X", "X");
        // Deployer is `this` (the test contract)
        assertEq(freshVault.owner(), address(this));

        freshVault.transferOwnership(user1);
        // Owner is still deployer until acceptance
        assertEq(freshVault.owner(), address(this));
        assertEq(freshVault.pendingOwner(), user1);

        vm.prank(user1);
        freshVault.acceptOwnership();
        assertEq(freshVault.owner(), user1);
        assertEq(freshVault.pendingOwner(), address(0));
    }

    // ============ Fee-on-transfer guard ============

    function test_RevertWhen_FeeOnTransferAsset_deposit() public {
        MockFeeOnTransferERC20 fotAsset = new MockFeeOnTransferERC20("FOT", "FOT");
        StakingVault fotVault = new StakingVault(IERC20(address(fotAsset)), "FOT-V", "FOT-V");
        fotVault.transferOwnership(owner);
        vm.prank(owner);
        fotVault.acceptOwnership();

        fotAsset.mint(user1, 1000e18);
        vm.prank(user1);
        fotAsset.approve(address(fotVault), type(uint256).max);

        address[] memory addrs = new address[](1);
        addrs[0] = user1;
        uint256[] memory caps = new uint256[](1);
        caps[0] = 1000e18;
        vm.prank(owner);
        fotVault.setDepositorsWhitelistDepositAmounts(addrs, caps);

        vm.prank(user1);
        vm.expectRevert(StakingVault.StakingVault__FeeOnTransferNotSupported.selector);
        fotVault.deposit(100e18, user1);
    }

    function test_RevertWhen_FeeOnTransferAsset_mint() public {
        MockFeeOnTransferERC20 fotAsset = new MockFeeOnTransferERC20("FOT", "FOT");
        StakingVault fotVault = new StakingVault(IERC20(address(fotAsset)), "FOT-V", "FOT-V");
        fotVault.transferOwnership(owner);
        vm.prank(owner);
        fotVault.acceptOwnership();

        fotAsset.mint(user1, 1000e18);
        vm.prank(user1);
        fotAsset.approve(address(fotVault), type(uint256).max);

        address[] memory addrs = new address[](1);
        addrs[0] = user1;
        uint256[] memory caps = new uint256[](1);
        caps[0] = 1000e18;
        vm.prank(owner);
        fotVault.setDepositorsWhitelistDepositAmounts(addrs, caps);

        vm.prank(user1);
        vm.expectRevert(StakingVault.StakingVault__FeeOnTransferNotSupported.selector);
        fotVault.mint(100e18 * SCALE, user1);
    }

    // ============ Reentrancy guard ============
    //
    // Coverage requirement: `nonReentrant` must be present on all four entry points
    // (deposit, mint, redeem, withdraw). Each test below uses one of the four as the
    // OUTER call. The mock asset's transferFrom (deposit/mint) or transfer (redeem/withdraw)
    // callback reenters `deposit` (any nonReentrant target works). If any outer entry point
    // loses `nonReentrant`, its test would no longer revert with ReentrancyGuardReentrantCall.

    /// @dev Bootstraps a fresh vault + reentrant-asset + whitelisted user1 with a 500-asset
    ///      seeded deposit (so user1 has shares for redeem/withdraw outer-call tests).
    function _setupReentrancyHarness() internal returns (StakingVault reVault, MockReentrantERC20 reAsset) {
        reAsset = new MockReentrantERC20("RE", "RE");
        reVault = new StakingVault(IERC20(address(reAsset)), "RE-V", "RE-V");
        reVault.transferOwnership(owner);
        vm.prank(owner);
        reVault.acceptOwnership();

        reAsset.mint(user1, 10000e18);
        vm.prank(user1);
        reAsset.approve(address(reVault), type(uint256).max);

        address[] memory addrs = new address[](1);
        addrs[0] = user1;
        uint256[] memory caps = new uint256[](1);
        caps[0] = 1000e18;
        vm.prank(owner);
        reVault.setDepositorsWhitelistDepositAmounts(addrs, caps);

        // Seed a deposit so user1 has shares for redeem/withdraw outer calls
        vm.prank(user1);
        reVault.deposit(500e18, user1);
    }

    function test_RevertWhen_ReentrantCall_outerDeposit() public {
        (StakingVault reVault, MockReentrantERC20 reAsset) = _setupReentrancyHarness();

        reAsset.arm(
            IStakingVaultReentry(address(reVault)),
            MockReentrantERC20.Mode.ReenterDeposit,
            10e18,
            user1
        );

        vm.prank(user1);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        reVault.deposit(100e18, user1);
    }

    function test_RevertWhen_ReentrantCall_outerMint() public {
        (StakingVault reVault, MockReentrantERC20 reAsset) = _setupReentrancyHarness();

        reAsset.arm(
            IStakingVaultReentry(address(reVault)),
            MockReentrantERC20.Mode.ReenterDeposit,
            10e18,
            user1
        );

        vm.prank(user1);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        reVault.mint(100e18 * SCALE, user1);
    }

    function test_RevertWhen_ReentrantCall_outerRedeem() public {
        (StakingVault reVault, MockReentrantERC20 reAsset) = _setupReentrancyHarness();

        // Reenter deposit from the asset's transfer callback (outer = redeem → safeTransfer)
        reAsset.arm(
            IStakingVaultReentry(address(reVault)),
            MockReentrantERC20.Mode.ReenterDeposit,
            10e18,
            user1
        );

        vm.prank(user1);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        reVault.redeem(100e18 * SCALE, user1, user1);
    }

    function test_RevertWhen_ReentrantCall_outerWithdraw() public {
        (StakingVault reVault, MockReentrantERC20 reAsset) = _setupReentrancyHarness();

        reAsset.arm(
            IStakingVaultReentry(address(reVault)),
            MockReentrantERC20.Mode.ReenterDeposit,
            10e18,
            user1
        );

        vm.prank(user1);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        reVault.withdraw(100e18, user1, user1);
    }

    /// @dev Sanity check that the mock actually reenters when armed (otherwise the four
    ///      tests above could pass for the wrong reason — they'd revert because the
    ///      callback fails, not because nonReentrant fires).
    function test_reentrantMock_armingActuallyTriggersReentry() public {
        (StakingVault reVault, MockReentrantERC20 reAsset) = _setupReentrancyHarness();

        // Arm to reenter MINT (different target from deposit) so we can confirm the
        // ReentrancyGuardReentrantCall selector matches even when target != outer.
        reAsset.arm(
            IStakingVaultReentry(address(reVault)),
            MockReentrantERC20.Mode.ReenterMint,
            10e18 * SCALE,
            user1
        );

        vm.prank(user1);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        reVault.deposit(100e18, user1);
    }

    // ============ Underfunded vault: proportional distribution ============

    function test_underfundedVault_proportionalDistribution() public {
        // Two users each whitelisted for 500
        _whitelistOne(user1, 500e18);
        _whitelistOne(user2, 500e18);

        vm.prank(user1);
        vault.deposit(500e18, user1);
        vm.prank(user2);
        vault.deposit(500e18, user2);
        assertEq(vault.totalAssets(), 1000e18);

        // Simulate asset loss: half the assets vanish from the vault (e.g., rebase, hack, etc.)
        asset.burn(address(vault), 500e18);
        assertEq(vault.totalAssets(), 500e18);

        uint256 user1AssetBefore = asset.balanceOf(user1);
        uint256 user2AssetBefore = asset.balanceOf(user2);
        uint256 user1Shares = vault.balanceOf(user1);
        uint256 user2Shares = vault.balanceOf(user2);

        // Each user redeems all their shares
        vm.prank(user1);
        vault.redeem(user1Shares, user1, user1);
        vm.prank(user2);
        vault.redeem(user2Shares, user2, user2);

        uint256 user1Received = asset.balanceOf(user1) - user1AssetBefore;
        uint256 user2Received = asset.balanceOf(user2) - user2AssetBefore;

        // Each receives ~250 (proportional split of 500 between equal shareholders)
        assertApproxEqAbs(user1Received, 250e18, 1e12);
        assertApproxEqAbs(user2Received, 250e18, 1e12);

        // Critical: BOTH users' principal restored to 0 — cap-room decouples from asset loss
        assertEq(vault.depositedPrincipal(user1), 0);
        assertEq(vault.depositedPrincipal(user2), 0);
        assertEq(vault.maxDeposit(user1), 500e18);
        assertEq(vault.maxDeposit(user2), 500e18);
    }

    // ============ Standard ERC4626 / view ============

    function test_maxFunctions_zeroBeforeWhitelist() public view {
        // F-4 fix: maxDeposit reflects actual capacity (0 before whitelist)
        assertEq(vault.maxDeposit(user1), 0);
        assertEq(vault.maxMint(user1), 0);
        assertEq(vault.maxWithdraw(user1), 0);
        assertEq(vault.maxRedeem(user1), 0);
    }

    function test_maxDeposit_reflectsRemainingCap() public {
        _whitelistOne(user1, 1000e18);
        assertEq(vault.maxDeposit(user1), 1000e18);
        vm.prank(user1);
        vault.deposit(300e18, user1);
        assertEq(vault.maxDeposit(user1), 700e18);
    }

    function test_totalAssets() public {
        _whitelistOne(user1, 1000e18);
        assertEq(vault.totalAssets(), 0);
        vm.prank(user1);
        vault.deposit(1000e18, user1);
        assertEq(vault.totalAssets(), 1000e18);

        asset.mint(address(vault), 100e18);
        assertEq(vault.totalAssets(), 1100e18);
    }

    function test_multipleUsers_independentCaps() public {
        _whitelistOne(user1, 1000e18);
        _whitelistOne(user2, 500e18);

        vm.prank(user1);
        vault.deposit(1000e18, user1);
        assertEq(vault.maxDeposit(user1), 0);

        vm.prank(user2);
        vault.deposit(500e18, user2);
        assertEq(vault.maxDeposit(user2), 0);

        vm.prank(user1);
        vault.redeem(500e18 * SCALE, user1, user1);
        assertEq(vault.maxDeposit(user1), 500e18);

        // user2's cap unchanged
        assertEq(vault.maxDeposit(user2), 0);
    }
}

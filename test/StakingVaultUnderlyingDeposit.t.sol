// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {StakingVault} from "../contracts/utils/StakingVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC4626Vault} from "./mocks/MockERC4626Vault.sol";
import {MockReentrantERC20, IStakingVaultReentry} from "./mocks/MockReentrantERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Tests for `depositFromUnderlyingAsset` — the nested-vault convenience path where
///         StakingVault.asset() is itself an ERC4626 whose asset() is USDC. The caller supplies
///         USDC; the vault wraps it into underlying-vault shares and deposits those here.
contract StakingVaultUnderlyingDepositTest is Test {
    StakingVault public vault; // asset() == underlyingVault
    MockERC4626Vault public underlyingVault; // asset() == usdc
    MockERC20 public usdc; // the "underlying asset"

    address public owner;
    address public user1;
    address public user2;

    /// @dev StakingVault._decimalsOffset() == 6, and a fresh underlyingVault is 1:1, so at price 1
    ///      `1` underlying-vault-share == `SCALE` StakingVault shares.
    uint256 internal constant SCALE = 10 ** 6;

    event DepositorWhitelisted(address indexed depositor, uint256 cap, uint256 currentPrincipal);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        usdc = new MockERC20("USD Coin", "USDC");
        underlyingVault = new MockERC4626Vault(IERC20(address(usdc)), "Underlying Vault", "uVAULT");
        vault = new StakingVault(IERC20(address(underlyingVault)), "Staking Vault", "sVAULT");
        vault.transferOwnership(owner);
        vm.prank(owner);
        vault.acceptOwnership();

        usdc.mint(user1, 10_000e18);
        usdc.mint(user2, 10_000e18);

        // For depositFromUnderlyingAsset the caller only ever approves USDC to the StakingVault.
        vm.prank(user1);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        usdc.approve(address(vault), type(uint256).max);
    }

    function _whitelistOne(address user, uint256 cap) internal {
        address[] memory addrs = new address[](1);
        addrs[0] = user;
        uint256[] memory caps = new uint256[](1);
        caps[0] = cap;
        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(addrs, caps);
    }

    /// @dev Raise underlyingVault's share price by donating `usdcAmount` USDC directly to it,
    ///      after a `seed` base deposit so totalSupply > 0.
    function _inflateUnderlyingVault(uint256 seed, uint256 donation) internal {
        usdc.mint(address(this), seed + donation);
        usdc.approve(address(underlyingVault), seed);
        underlyingVault.deposit(seed, address(this));
        usdc.mint(address(underlyingVault), donation);
    }

    /// @dev Simulate StakingVault-layer yield: acquire `uShares` of underlyingVault and transfer
    ///      them directly into the StakingVault (raising totalAssets without minting vault shares).
    function _reimburseStakingVault(uint256 usdcForUShares) internal {
        usdc.mint(address(this), usdcForUShares);
        usdc.approve(address(underlyingVault), usdcForUShares);
        uint256 uShares = underlyingVault.deposit(usdcForUShares, address(this));
        underlyingVault.transfer(address(vault), uShares);
    }

    // ============ Wiring ============

    function test_assetWiring() public view {
        assertEq(vault.asset(), address(underlyingVault));
        assertEq(vault.underlyingAsset(), address(usdc));
        assertEq(underlyingVault.asset(), address(usdc));
    }

    // ============ Happy path ============

    function test_depositFromUnderlyingAsset_basic() public {
        _whitelistOne(user1, 1000e18);

        uint256 usdcIn = 100e18;
        vm.prank(user1);
        uint256 shares = vault.depositFromUnderlyingAsset(usdcIn, user1);

        // Fresh underlyingVault: 100 USDC -> 100 uShares. Fresh StakingVault: 100 uShares -> 100*SCALE.
        assertEq(shares, 100e18 * SCALE);
        assertEq(vault.balanceOf(user1), 100e18 * SCALE);

        // The StakingVault now custodies the underlying-vault shares; the USDC sits in underlyingVault.
        assertEq(underlyingVault.balanceOf(address(vault)), 100e18);
        assertEq(usdc.balanceOf(address(underlyingVault)), 100e18);
        assertEq(usdc.balanceOf(user1), 10_000e18 - 100e18);

        // Principal is charged in underlying-vault-share units, not USDC units (here they coincide).
        assertEq(vault.depositedPrincipal(user1), 100e18);
        assertEq(vault.maxDeposit(user1), 900e18);

        // No dust left behind in the vault, no lingering approval.
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(usdc.allowance(address(vault), address(underlyingVault)), 0);
    }

    function test_depositFromUnderlyingAsset_emitsEvents() public {
        _whitelistOne(user1, 1000e18);

        vm.expectEmit(true, true, false, true, address(vault));
        emit Deposit(user1, user1, 100e18, 100e18 * SCALE);
        vm.expectEmit(true, false, false, true, address(vault));
        emit DepositorWhitelisted(user1, 1000e18, 100e18);

        vm.prank(user1);
        vault.depositFromUnderlyingAsset(100e18, user1);
    }

    /// @dev Two fresh, independent stacks: the USDC convenience path must mint exactly what the
    ///      manual two-hop (underlyingVault.deposit -> vault.deposit) mints for the same USDC.
    function test_depositFromUnderlyingAsset_equivalentToManualTwoStep() public {
        // Stack A: user1 uses the convenience path on `vault`.
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        uint256 sharesA = vault.depositFromUnderlyingAsset(500e18, user1);

        // Stack B: identical fresh stack, user2 performs the two hops manually.
        MockERC20 usdcB = new MockERC20("USD Coin", "USDC");
        MockERC4626Vault underlyingVaultB = new MockERC4626Vault(IERC20(address(usdcB)), "Underlying Vault", "uVAULT");
        StakingVault vaultB = new StakingVault(IERC20(address(underlyingVaultB)), "Staking Vault", "sVAULT");
        // owner of vaultB is this test contract; whitelist user2 directly
        address[] memory addrs = new address[](1);
        addrs[0] = user2;
        uint256[] memory caps = new uint256[](1);
        caps[0] = 1000e18;
        vaultB.setDepositorsWhitelistDepositAmounts(addrs, caps);

        usdcB.mint(user2, 10_000e18);
        vm.startPrank(user2);
        usdcB.approve(address(underlyingVaultB), 500e18);
        uint256 uShares = underlyingVaultB.deposit(500e18, user2);
        underlyingVaultB.approve(address(vaultB), uShares);
        uint256 sharesB = vaultB.deposit(uShares, user2);
        vm.stopPrank();

        assertEq(sharesA, sharesB);
        assertEq(vault.depositedPrincipal(user1), vaultB.depositedPrincipal(user2));
        assertEq(vault.balanceOf(user1), vaultB.balanceOf(user2));
    }

    /// @dev CRITICAL: the share-price snapshot must reproduce `previewDeposit` evaluated BEFORE the
    ///      wrapped shares enter the vault's balance. After StakingVault-layer yield (price > 1),
    ///      depositFromUnderlyingAsset must mint EXACTLY `previewDeposit(receivedUShares)`.
    function test_depositFromUnderlyingAsset_matchesPreviewDeposit_afterStakingVaultYield() public {
        _whitelistOne(user1, 10_000e18);
        _whitelistOne(user2, 10_000e18);

        // user1 establishes supply, then the team reimburses the StakingVault (yield -> price up).
        vm.prank(user1);
        uint256 user1Shares = vault.depositFromUnderlyingAsset(1000e18, user1);
        _reimburseStakingVault(500e18); // vault.totalAssets() == 1500 uShares, supply == 1000*SCALE

        // Predict what a clean two-hop would mint, at the CURRENT (elevated) price.
        uint256 predictedUShares = underlyingVault.previewDeposit(1000e18);
        uint256 expectedShares = vault.previewDeposit(predictedUShares);

        vm.prank(user2);
        uint256 user2Shares = vault.depositFromUnderlyingAsset(1000e18, user2);

        // Exact match with the canonical pre-deposit-price computation.
        assertEq(user2Shares, expectedShares);
        // Same USDC, but fewer StakingVault shares than user1 because each share now costs more.
        assertLt(user2Shares, user1Shares);
        // Principal charged in underlying-vault-share units.
        assertEq(vault.depositedPrincipal(user2), predictedUShares);
    }

    /// @dev Principal is denominated in underlying-vault shares, NOT USDC: when the underlyingVault's
    ///      own price is > 1, depositing USDC yields fewer uShares, and that smaller number is what
    ///      counts against the cap.
    function test_depositFromUnderlyingAsset_principalInUnderlyingShareUnits() public {
        _inflateUnderlyingVault(100e18, 100e18); // underlyingVault price == 2x
        _whitelistOne(user1, 1000e18);

        uint256 predictedUShares = underlyingVault.previewDeposit(100e18); // ~50e18
        assertLt(predictedUShares, 100e18);

        vm.prank(user1);
        uint256 shares = vault.depositFromUnderlyingAsset(100e18, user1);

        assertEq(vault.depositedPrincipal(user1), predictedUShares);
        assertEq(underlyingVault.balanceOf(address(vault)), predictedUShares);
        // Fresh StakingVault (first depositor) -> shares == uShares * SCALE.
        assertEq(shares, predictedUShares * SCALE);
        assertEq(vault.maxDeposit(user1), 1000e18 - predictedUShares);
    }

    function test_depositFromUnderlyingAsset_thenRedeem_roundTrip() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        uint256 shares = vault.depositFromUnderlyingAsset(100e18, user1);

        // Redeem all StakingVault shares -> caller receives the StakingVault asset (uShares).
        vm.prank(user1);
        uint256 assetsOut = vault.redeem(shares, user1, user1);

        assertEq(assetsOut, 100e18);
        assertEq(underlyingVault.balanceOf(user1), 100e18);
        assertEq(vault.balanceOf(user1), 0);
        assertEq(vault.depositedPrincipal(user1), 0);
        assertEq(vault.maxDeposit(user1), 1000e18);

        // And those uShares are freely redeemable from the underlyingVault for the original USDC.
        vm.prank(user1);
        uint256 usdcOut = underlyingVault.redeem(100e18, user1, user1);
        assertEq(usdcOut, 100e18);
    }

    // ============ Guards ============

    function test_RevertWhen_ReceiverMismatch() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(StakingVault.StakingVault__ReceiverMismatch.selector, user1, user2));
        vault.depositFromUnderlyingAsset(100e18, user2);
    }

    function test_RevertWhen_ZeroAmount() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(user1);
        vm.expectRevert(StakingVault.StakingVault__ZeroAmount.selector);
        vault.depositFromUnderlyingAsset(0, user1);
    }

    function test_RevertWhen_ExceedsCap() public {
        _whitelistOne(user1, 50e18); // cap in uShares; 100 USDC -> 100 uShares > 50
        vm.prank(user1);
        vm.expectRevert(); // OZ ERC4626ExceededMaxDeposit
        vault.depositFromUnderlyingAsset(100e18, user1);
    }

    function test_RevertWhen_NotWhitelisted() public {
        vm.prank(user1);
        vm.expectRevert(); // cap 0 -> maxDeposit 0 -> ERC4626ExceededMaxDeposit
        vault.depositFromUnderlyingAsset(100e18, user1);
    }

    function test_RevertWhen_Paused() public {
        _whitelistOne(user1, 1000e18);
        vm.prank(owner);
        vault.pause();

        vm.prank(user1);
        vm.expectRevert(); // OZ EnforcedPause
        vault.depositFromUnderlyingAsset(100e18, user1);
    }

    /// @dev Dust that wraps into zero StakingVault shares must revert atomically (caller keeps USDC),
    ///      rather than silently consuming USDC for nothing. Force price >> input so shares floor to 0.
    function test_RevertWhen_WrapsToZeroShares() public {
        // Inflate StakingVault price so far that 1 wei of uShares mints 0 StakingVault shares.
        _whitelistOne(user1, type(uint256).max);
        vm.prank(user1);
        vault.depositFromUnderlyingAsset(1000e18, user1); // establish supply == 1000*SCALE

        // Reimburse so many uShares that (1 wei uShare * (supply + 1e6)) / (assets + 1) floors to 0
        // (assetsBefore exceeds supplyBefore once the donated shares dwarf the original principal).
        _reimburseStakingVault(1_000_000_000e18);

        // 1 wei of USDC wraps to ~1 uShare, which against the inflated price mints 0 vault shares.
        _whitelistOne(user2, type(uint256).max);
        vm.prank(user2);
        vm.expectRevert(StakingVault.StakingVault__ZeroShares.selector);
        vault.depositFromUnderlyingAsset(1, user2);
    }

    // ============ Reentrancy ============

    /// @dev `depositFromUnderlyingAsset` must hold `nonReentrant`: a reentrant USDC token that
    ///      calls back into the vault during the pull is rejected.
    function test_RevertWhen_ReentrantCall_outerDepositFromUnderlyingAsset() public {
        MockReentrantERC20 reUsdc = new MockReentrantERC20("RE-USDC", "REUSDC");
        MockERC4626Vault reUnderlying = new MockERC4626Vault(IERC20(address(reUsdc)), "RE-U", "REU");
        StakingVault reVault = new StakingVault(IERC20(address(reUnderlying)), "RE-V", "REV");

        address[] memory addrs = new address[](1);
        addrs[0] = user1;
        uint256[] memory caps = new uint256[](1);
        caps[0] = 1000e18;
        reVault.setDepositorsWhitelistDepositAmounts(addrs, caps);

        reUsdc.mint(user1, 1000e18);
        vm.prank(user1);
        reUsdc.approve(address(reVault), type(uint256).max);

        // Arm the USDC to reenter deposit() when it's pulled into the vault.
        reUsdc.arm(IStakingVaultReentry(address(reVault)), MockReentrantERC20.Mode.ReenterDeposit, 10e18, user1);

        vm.prank(user1);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        reVault.depositFromUnderlyingAsset(100e18, user1);
    }
}

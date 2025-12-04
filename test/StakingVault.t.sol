// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {StakingVault} from "../contracts/utils/StakingVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingVaultTest is Test {
    StakingVault public vault;
    MockERC20 public asset;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    // Events
    event DepositorWhitelisted(address indexed depositor, uint256 amount);
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy mock asset
        asset = new MockERC20("Test Token", "TEST");

        // Deploy vault
        vault = new StakingVault(IERC20(address(asset)), "Test Vault", "vTEST");
        vault.transferOwnership(owner);

        // Fund users
        asset.mint(user1, 10000e18);
        asset.mint(user2, 10000e18);
        asset.mint(user3, 10000e18);

        // Approve vault
        vm.prank(user1);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(user3);
        asset.approve(address(vault), type(uint256).max);
    }

    // ============ Constructor Tests ============

    function test_constructor() public view {
        assertEq(address(vault.asset()), address(asset));
        assertEq(vault.name(), "Test Vault");
        assertEq(vault.symbol(), "vTEST");
        assertEq(vault.owner(), owner);
    }

    // ============ Depositor Whitelist Tests ============

    function test_setDepositorsWhitelistDepositAmounts_single() public {
        address[] memory depositors = new address[](1);
        depositors[0] = user1;

        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1000e18;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit DepositorWhitelisted(user1, 1000e18);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        assertEq(vault.depositWhitelist(user1), 1000e18);
    }

    function test_setDepositorsWhitelistDepositAmounts_multiple() public {
        address[] memory depositors = new address[](3);
        depositors[0] = user1;
        depositors[1] = user2;
        depositors[2] = user3;

        uint256[] memory depositAmounts = new uint256[](3);
        depositAmounts[0] = 1000e18;
        depositAmounts[1] = 2000e18;
        depositAmounts[2] = 3000e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        assertEq(vault.depositWhitelist(user1), 1000e18);
        assertEq(vault.depositWhitelist(user2), 2000e18);
        assertEq(vault.depositWhitelist(user3), 3000e18);
    }

    function test_setDepositorsWhitelistDepositAmounts_canUpdate() public {
        // Set initial amount
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1000e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);
        assertEq(vault.depositWhitelist(user1), 1000e18);

        // Update amount
        depositAmounts[0] = 2000e18;
        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);
        assertEq(vault.depositWhitelist(user1), 2000e18);
    }

    function test_RevertWhen_NonOwnerSetsWhitelist() public {
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1000e18;

        vm.prank(user1);
        vm.expectRevert();
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);
    }

    function test_RevertWhen_ArrayLengthMismatch() public {
        address[] memory depositors = new address[](2);
        depositors[0] = user1;
        depositors[1] = user2;

        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1000e18;

        vm.prank(owner);
        vm.expectRevert("Array length mismatch");
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);
    }

    // ============ Deposit Tests ============

    function test_deposit() public {
        // Whitelist user1
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1000e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        uint256 depositAmount = 100e18;

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit Deposit(user1, user1, depositAmount, depositAmount);
        uint256 shares = vault.deposit(depositAmount, user1);

        assertEq(shares, depositAmount);
        assertEq(vault.balanceOf(user1), depositAmount);
        assertEq(asset.balanceOf(address(vault)), depositAmount);
        assertEq(vault.depositWhitelist(user1), 900e18); // 1000 - 100
    }

    function test_deposit_toAnotherReceiver() public {
        // Whitelist user1
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1000e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        uint256 depositAmount = 100e18;

        vm.prank(user1);
        uint256 shares = vault.deposit(depositAmount, user2);

        assertEq(shares, depositAmount);
        assertEq(vault.balanceOf(user2), depositAmount);
        assertEq(vault.depositWhitelist(user1), 900e18);
    }

    function test_deposit_multipleDeposits() public {
        // Whitelist user1
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1000e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        // First deposit
        vm.prank(user1);
        vault.deposit(300e18, user1);
        assertEq(vault.depositWhitelist(user1), 700e18);

        // Second deposit
        vm.prank(user1);
        vault.deposit(200e18, user1);
        assertEq(vault.depositWhitelist(user1), 500e18);

        assertEq(vault.balanceOf(user1), 500e18);
    }

    function test_RevertWhen_DepositExceedsWhitelist() public {
        // Whitelist user1 with small amount
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 50e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        vm.prank(user1);
        vm.expectRevert(); // Underflow when trying to subtract more than available
        vault.deposit(100e18, user1);
    }

    function test_RevertWhen_DepositWithoutWhitelist() public {
        vm.prank(user1);
        vm.expectRevert(); // Underflow when whitelist amount is 0
        vault.deposit(100e18, user1);
    }

    // ============ Mint Tests ============

    function test_mint() public {
        // Whitelist user1
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1000e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        uint256 sharesToMint = 100e18;

        vm.prank(user1);
        uint256 assets = vault.mint(sharesToMint, user1);

        assertEq(assets, sharesToMint); // 1:1 initially
        assertEq(vault.balanceOf(user1), sharesToMint);
    }

    // ============ Redeem Tests ============

    function test_redeem() public {
        // Whitelist and deposit
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1000e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        vm.prank(user1);
        vault.deposit(1000e18, user1);

        assertEq(vault.depositWhitelist(user1), 0); // All used up

        // Redeem half
        uint256 sharesToRedeem = 500e18;
        vm.prank(user1);
        uint256 assets = vault.redeem(sharesToRedeem, user1, user1);

        assertEq(assets, 500e18);
        assertEq(vault.balanceOf(user1), 500e18);
        assertEq(vault.depositWhitelist(user1), 500e18); // Replenished
        assertEq(asset.balanceOf(user1), 9500e18); // 10000 - 1000 + 500
    }

    function test_redeem_full() public {
        // Whitelist and deposit
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1000e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        vm.prank(user1);
        vault.deposit(1000e18, user1);

        // Redeem all
        vm.prank(user1);
        uint256 assets = vault.redeem(1000e18, user1, user1);

        assertEq(assets, 1000e18);
        assertEq(vault.balanceOf(user1), 0);
        assertEq(vault.depositWhitelist(user1), 1000e18); // Fully replenished
        assertEq(asset.balanceOf(user1), 10000e18); // Back to starting balance
    }

    function test_redeem_withApproval() public {
        // Whitelist and deposit
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1000e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        vm.prank(user1);
        vault.deposit(1000e18, user1);

        // User1 approves user2
        vm.prank(user1);
        vault.approve(user2, 500e18);

        // User2 redeems on behalf of user1
        vm.prank(user2);
        uint256 assets = vault.redeem(500e18, user2, user1);

        assertEq(assets, 500e18);
        assertEq(vault.balanceOf(user1), 500e18);
        assertEq(asset.balanceOf(user2), 10500e18); // Got the redeemed assets
        assertEq(vault.depositWhitelist(user1), 500e18); // Replenished
    }

    // ============ Withdraw Tests ============

    function test_withdraw() public {
        // Whitelist and deposit
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1000e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        vm.prank(user1);
        vault.deposit(1000e18, user1);

        // Withdraw
        vm.prank(user1);
        uint256 shares = vault.withdraw(500e18, user1, user1);

        assertEq(shares, 500e18);
        assertEq(vault.balanceOf(user1), 500e18);
        assertEq(vault.depositWhitelist(user1), 500e18); // Replenished
    }

    // ============ Multiple Users Tests ============

    function test_multipleUsers_independentWhitelists() public {
        // Setup two users
        address[] memory depositors = new address[](2);
        depositors[0] = user1;
        depositors[1] = user2;
        uint256[] memory depositAmounts = new uint256[](2);
        depositAmounts[0] = 1000e18;
        depositAmounts[1] = 500e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        // User1 deposits
        vm.prank(user1);
        vault.deposit(1000e18, user1);
        assertEq(vault.depositWhitelist(user1), 0);

        // User2 deposits
        vm.prank(user2);
        vault.deposit(500e18, user2);
        assertEq(vault.depositWhitelist(user2), 0);

        // User1 redeems
        vm.prank(user1);
        vault.redeem(500e18, user1, user1);
        assertEq(vault.depositWhitelist(user1), 500e18);

        // User2's whitelist unchanged
        assertEq(vault.depositWhitelist(user2), 0);

        // User2 redeems
        vm.prank(user2);
        vault.redeem(250e18, user2, user2);
        assertEq(vault.depositWhitelist(user2), 250e18);

        // User1's whitelist unchanged from previous
        assertEq(vault.depositWhitelist(user1), 500e18);
    }

    // ============ Standard ERC4626 Tests ============

    function test_previewFunctions() public {
        // Whitelist and deposit
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1000e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        vm.prank(user1);
        vault.deposit(1000e18, user1);

        // Preview functions should work
        uint256 previewDeposit = vault.previewDeposit(100e18);
        assertGt(previewDeposit, 0);

        uint256 previewMint = vault.previewMint(100e18);
        assertGt(previewMint, 0);

        uint256 previewWithdraw = vault.previewWithdraw(100e18);
        assertGt(previewWithdraw, 0);

        uint256 previewRedeem = vault.previewRedeem(100e18);
        assertGt(previewRedeem, 0);
    }

    function test_maxFunctions() public view {
        // Max functions should return reasonable values
        assertEq(vault.maxDeposit(user1), type(uint256).max);
        assertEq(vault.maxMint(user1), type(uint256).max);
        assertEq(vault.maxWithdraw(user1), 0); // No deposits yet
        assertEq(vault.maxRedeem(user1), 0); // No deposits yet
    }

    function test_totalAssets() public {
        // Whitelist and deposit
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1000e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        assertEq(vault.totalAssets(), 0);

        vm.prank(user1);
        vault.deposit(1000e18, user1);
        assertEq(vault.totalAssets(), 1000e18);

        // If someone sends tokens directly, totalAssets should increase
        asset.mint(address(vault), 100e18);
        assertEq(vault.totalAssets(), 1100e18);
    }

    function test_convertToShares_and_convertToAssets() public {
        // Whitelist and deposit
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 2000e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        vm.prank(user1);
        vault.deposit(1000e18, user1);

        // Initially 1:1
        assertEq(vault.convertToShares(1000e18), 1000e18);
        assertEq(vault.convertToAssets(1000e18), 1000e18);

        // If yield is added (e.g., direct transfer), share price increases
        asset.mint(address(vault), 100e18);

        // 1100 assets / 1000 shares = 1.1 assets per share
        assertApproxEqAbs(vault.convertToAssets(1000e18), 1100e18, 1);
        // To get 1000 assets, need ~909 shares (1000 / 1.1)
        assertApproxEqAbs(vault.convertToShares(1000e18), 909090909090909090909, 1e15);
    }

    function test_RevertWhen_WithdrawExceedsBalance() public {
        // Whitelist and deposit
        address[] memory depositors = new address[](1);
        depositors[0] = user1;
        uint256[] memory depositAmounts = new uint256[](1);
        depositAmounts[0] = 1000e18;

        vm.prank(owner);
        vault.setDepositorsWhitelistDepositAmounts(depositors, depositAmounts);

        vm.prank(user1);
        vault.deposit(500e18, user1);

        // Try to withdraw more than deposited
        vm.prank(user1);
        vm.expectRevert();
        vault.withdraw(600e18, user1, user1);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import "./mocks/TestERC20.sol";
import "./mocks/TestERC4626Vault.sol";
import "../contracts/LendingAssetVault.sol";

contract LendingAssetVaultTest is Test {
    TestERC20 _asset;
    TestERC4626Vault _testVault;
    LendingAssetVault _lendingAssetVault;

    function setUp() public {
        _asset = new TestERC20("Test Token", "tTEST");
        _testVault = new TestERC4626Vault(address(_asset));
        _lendingAssetVault = new LendingAssetVault("Test LAV", "tLAV", address(_asset));

        _asset.approve(address(_testVault), _asset.totalSupply());
        _asset.approve(address(_lendingAssetVault), _asset.totalSupply());
        _lendingAssetVault.setVaultWhitelist(address(_testVault), true);
    }

    function test_deposit() public {
        _lendingAssetVault.deposit(10e18, address(this));
        assertEq(_lendingAssetVault.totalSupply(), _lendingAssetVault.balanceOf(address(this)));
    }

    function test_withdrawNoCbrDiff() public {
        uint256 _depAmt = 10e18;
        _lendingAssetVault.deposit(_depAmt, address(this));
        assertEq(_lendingAssetVault.totalSupply(), _depAmt);
        vm.roll(block.timestamp + 1);
        _lendingAssetVault.withdraw(_depAmt / 2, address(this), address(this));
        assertEq(_lendingAssetVault.totalSupply(), _lendingAssetVault.balanceOf(address(this)));
        assertEq(_asset.balanceOf(address(this)), _asset.totalSupply() - _depAmt / 2);
    }

    function test_redeemNoCbrDiff() public {
        uint256 _depAmt = 10e18;
        _lendingAssetVault.deposit(_depAmt, address(this));
        assertEq(_lendingAssetVault.totalSupply(), _depAmt);
        vm.roll(block.timestamp + 1);
        _lendingAssetVault.redeem(_depAmt / 2, address(this), address(this));
        assertEq(_lendingAssetVault.totalSupply(), _lendingAssetVault.balanceOf(address(this)));
        assertEq(_asset.balanceOf(address(this)), _asset.totalSupply() - _depAmt / 2);
    }

    function test_vaultDepositAndWithdrawNoCbrChange() public {
        address[] memory vaults = new address[](1);
        vaults[0] = address(_testVault);
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 10e18;
        _lendingAssetVault.setVaultMaxAllocation(vaults, percentages);

        uint256 _lavDepAmt = 10e18;
        uint256 _extDepAmt = _lavDepAmt / 2;
        _lendingAssetVault.deposit(_lavDepAmt, address(this));
        assertEq(_lendingAssetVault.totalSupply(), _lavDepAmt);

        _testVault.depositFromLendingAssetVault(address(_lendingAssetVault), _extDepAmt);
        _testVault.withdrawToLendingAssetVault(address(_lendingAssetVault), _extDepAmt);

        vm.roll(block.timestamp + 1);
        _lendingAssetVault.withdraw(_lavDepAmt / 2, address(this), address(this));
        assertEq(_lendingAssetVault.totalSupply(), _lendingAssetVault.balanceOf(address(this)));
        assertEq(_asset.balanceOf(address(this)), _asset.totalSupply() - _lavDepAmt / 2);
    }

    function test_vaultDepositAndWithdrawWithCbrChange() public {
        address[] memory vaults = new address[](1);
        vaults[0] = address(_testVault);
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 10e18;
        _lendingAssetVault.setVaultMaxAllocation(vaults, percentages);

        uint256 _lavDepAmt = 10e18;
        uint256 _extDepAmt = _lavDepAmt / 2;
        _lendingAssetVault.deposit(_lavDepAmt, address(this));
        assertEq(_lendingAssetVault.totalSupply(), _lavDepAmt);

        _testVault.depositFromLendingAssetVault(address(_lendingAssetVault), _extDepAmt);
        _asset.transfer(address(_testVault), _extDepAmt);
        _testVault.withdrawToLendingAssetVault(address(_lendingAssetVault), _extDepAmt);

        vm.roll(block.timestamp + 1);
        _lendingAssetVault.withdraw(_lavDepAmt / 2, address(this), address(this));

        uint256 _optimalBal = _asset.totalSupply() - _lavDepAmt / 2 - _extDepAmt;
        assertEq(_asset.balanceOf(address(this)), _optimalBal);

        _testVault.withdrawToLendingAssetVault(
            address(_lendingAssetVault), _lendingAssetVault.vaultUtilization(address(_testVault))
        );
        assertEq(_lendingAssetVault.vaultUtilization(address(_testVault)), 0);
        assertApproxEqAbs(_lendingAssetVault.totalAssets(), _lavDepAmt, 1e2, "final totalAssets not valid");
    }

    function test_redeemFromVaultAll() public {
        uint256 _lavDepAmt = 10e18;
        uint256 _extDepAmt = _lavDepAmt / 2;
        _lendingAssetVault.deposit(_lavDepAmt, address(this));
        address[] memory vaults = new address[](1);
        vaults[0] = address(_testVault);
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 10e18;
        _lendingAssetVault.setVaultMaxAllocation(vaults, percentages);

        _testVault.depositFromLendingAssetVault(address(_lendingAssetVault), _extDepAmt);

        uint256 _initialTotalAssetsUtilized =
            _lendingAssetVault.totalAssets() - _lendingAssetVault.totalAvailableAssets();

        // vm.expectEmit(true, true, true, true);
        // emit ILendingAssetVault.RedeemFromVault(
        //   address(_testVault),
        //   _testVault.balanceOf(address(_lendingAssetVault)),
        //   _extDepAmt
        // );

        _lendingAssetVault.redeemFromVault(address(_testVault), 0);

        assertEq(_lendingAssetVault.vaultUtilization(address(_testVault)), 0);
        assertEq(
            _lendingAssetVault.totalAssets() - _lendingAssetVault.totalAvailableAssets(),
            _initialTotalAssetsUtilized - _extDepAmt
        );
        assertEq(_asset.balanceOf(address(_lendingAssetVault)), _lavDepAmt);
    }

    function test_redeemFromVaultPartial() public {
        uint256 _lavDepAmt = 10e18;
        uint256 _extDepAmt = _lavDepAmt / 2;
        _lendingAssetVault.deposit(_lavDepAmt, address(this));
        address[] memory vaults = new address[](1);
        vaults[0] = address(_testVault);
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 10e18;
        _lendingAssetVault.setVaultMaxAllocation(vaults, percentages);

        _testVault.depositFromLendingAssetVault(address(_lendingAssetVault), _extDepAmt);

        uint256 _redeemShares = _testVault.balanceOf(address(_lendingAssetVault)) / 2;
        uint256 _expectedAssets = _testVault.convertToAssets(_redeemShares);

        uint256 _initialVaultUtilization = _lendingAssetVault.vaultUtilization(address(_testVault));
        uint256 _initialTotalAssetsUtilized =
            _lendingAssetVault.totalAssets() - _lendingAssetVault.totalAvailableAssets();

        // vm.expectEmit(true, true, true, true);
        // emit ILendingAssetVault.RedeemFromVault(
        //   address(_testVault),
        //   _redeemShares,
        //   _expectedAssets
        // );

        _lendingAssetVault.redeemFromVault(address(_testVault), _redeemShares);

        assertEq(_lendingAssetVault.vaultUtilization(address(_testVault)), _initialVaultUtilization - _expectedAssets);
        assertEq(
            _lendingAssetVault.totalAssets() - _lendingAssetVault.totalAvailableAssets(),
            _initialTotalAssetsUtilized - _expectedAssets
        );
        assertEq(_asset.balanceOf(address(_lendingAssetVault)), _lavDepAmt - _extDepAmt + _expectedAssets);
    }

    function test_redeemFromVaultZeroShares() public {
        uint256 _lavDepAmt = 10e18;
        uint256 _extDepAmt = _lavDepAmt / 2;
        _lendingAssetVault.deposit(_lavDepAmt, address(this));
        address[] memory vaults = new address[](1);
        vaults[0] = address(_testVault);
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 10e18;
        _lendingAssetVault.setVaultMaxAllocation(vaults, percentages);

        _testVault.depositFromLendingAssetVault(address(_lendingAssetVault), _extDepAmt);

        uint256 _initialTotalAssetsUtilized =
            _lendingAssetVault.totalAssets() - _lendingAssetVault.totalAvailableAssets();

        uint256 _expectedShares = _testVault.balanceOf(address(_lendingAssetVault));
        uint256 _expectedAssets = _testVault.convertToAssets(_expectedShares);

        // vm.expectEmit(true, true, true, true);
        // emit ILendingAssetVault.RedeemFromVault(
        //   address(_testVault),
        //   _expectedShares,
        //   _expectedAssets
        // );

        _lendingAssetVault.redeemFromVault(address(_testVault), 0);

        assertEq(_lendingAssetVault.vaultUtilization(address(_testVault)), 0);
        assertEq(
            _lendingAssetVault.totalAssets() - _lendingAssetVault.totalAvailableAssets(),
            _initialTotalAssetsUtilized - _expectedAssets
        );
        assertEq(_asset.balanceOf(address(_lendingAssetVault)), _lavDepAmt);
    }

    function test_redeemFromVaultMoreThanAvailable() public {
        uint256 _lavDepAmt = 10e18;
        uint256 _extDepAmt = _lavDepAmt / 2;
        _lendingAssetVault.deposit(_lavDepAmt, address(this));
        address[] memory vaults = new address[](1);
        vaults[0] = address(_testVault);
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 10e18;
        _lendingAssetVault.setVaultMaxAllocation(vaults, percentages);

        _testVault.depositFromLendingAssetVault(address(_lendingAssetVault), _extDepAmt);

        uint256 _availableShares = _testVault.balanceOf(address(_lendingAssetVault));
        uint256 _moreThanAvailable = _availableShares + 1e18;

        vm.expectRevert();
        _lendingAssetVault.redeemFromVault(address(_testVault), _moreThanAvailable);
    }

    function test_depositToVault() public {
        uint256 _lavDepAmt = 10e18;
        uint256 _extDepAmt = _lavDepAmt / 2;
        _lendingAssetVault.deposit(_lavDepAmt, address(this));
        address[] memory vaults = new address[](1);
        vaults[0] = address(_testVault);
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 10e18;
        _lendingAssetVault.setVaultMaxAllocation(vaults, percentages);

        uint256 initialVaultUtilization = _lendingAssetVault.vaultUtilization(address(_testVault));
        uint256 initialTotalAssetsUtilized =
            _lendingAssetVault.totalAssets() - _lendingAssetVault.totalAvailableAssets();
        uint256 initialVaultShares = _testVault.balanceOf(address(_lendingAssetVault));

        _lendingAssetVault.depositToVault(address(_testVault), _extDepAmt);

        assertEq(
            _lendingAssetVault.vaultUtilization(address(_testVault)),
            initialVaultUtilization + _extDepAmt,
            "Vault utilization should increase"
        );
        assertEq(
            _lendingAssetVault.totalAssets() - _lendingAssetVault.totalAvailableAssets(),
            initialTotalAssetsUtilized + _extDepAmt,
            "Total assets utilized should increase"
        );
        assertGt(_testVault.balanceOf(address(_lendingAssetVault)), initialVaultShares, "Vault shares should increase");
    }

    function test_depositToVault_ZeroAmount() public {
        uint256 _lavDepAmt = 10e18;
        _lendingAssetVault.deposit(_lavDepAmt, address(this));
        address[] memory vaults = new address[](1);
        vaults[0] = address(_testVault);
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 10e18;
        _lendingAssetVault.setVaultMaxAllocation(vaults, percentages);

        vm.expectRevert();
        _lendingAssetVault.depositToVault(address(_testVault), 0);
    }

    function test_depositToVault_NotOwner() public {
        uint256 _lavDepAmt = 10e18;
        uint256 _extDepAmt = _lavDepAmt / 2;
        _lendingAssetVault.deposit(_lavDepAmt, address(this));
        address[] memory vaults = new address[](1);
        vaults[0] = address(_testVault);
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 10e18;
        _lendingAssetVault.setVaultMaxAllocation(vaults, percentages);

        address notOwner = makeAddr("notOwner");
        vm.startPrank(notOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, notOwner));
        _lendingAssetVault.depositToVault(address(_testVault), _extDepAmt);
        vm.stopPrank();
    }

    function test_frontrunWhitelistWithdraw() public {
        // enable lending asset from the vault
        address[] memory vaults = new address[](1);
        vaults[0] = address(_testVault);
        uint256[] memory percentages = new uint256[](1);
        percentages[0] = 10e18;
        _lendingAssetVault.setVaultMaxAllocation(vaults, percentages);

        // fund user
        address user = makeAddr("user");
        uint256 amount = 1 ether;
        _asset.transfer(user, amount * 2);
        vm.startPrank(user);

        // must deposit into test vault to change supply from zero
        _asset.approve(address(_testVault), amount);
        _testVault.deposit(amount, user);

        _asset.approve(address(_lendingAssetVault), amount);
        _lendingAssetVault.deposit(amount, user);
        vm.stopPrank();

        // test vault borrows the funds from the lending asset vault
        _testVault.depositFromLendingAssetVault(address(_lendingAssetVault), amount / 2);

        // simulate some profit in the test vault
        uint256 PRECISION = 100;
        uint256 convertToAssets = _testVault.convertToAssets(PRECISION);
        uint256 profit = 1 ether;
        _asset.transfer(address(_testVault), profit);
        assertGt(_testVault.convertToAssets(PRECISION), convertToAssets, "Profit not recorded");

        // fund attacker
        address attacker = makeAddr("attacker");
        uint256 attackerInitialAmount = 10 ether;
        _asset.transfer(attacker, attackerInitialAmount);

        // attacker frontruns whitelist withdraw and deposits to vault
        vm.startPrank(attacker);
        _asset.approve(address(_lendingAssetVault), attackerInitialAmount);
        _lendingAssetVault.deposit(attackerInitialAmount, attacker);
        _testVault.withdrawToLendingAssetVault(address(_lendingAssetVault), amount / 2);

        // attacker and user have the same amount of shares
        assertNotEq(_lendingAssetVault.balanceOf(attacker), _lendingAssetVault.balanceOf(user), "Not equal shares");

        vm.roll(block.timestamp + 1);
        _lendingAssetVault.redeem(_lendingAssetVault.balanceOf(attacker), attacker, attacker);
        // uint256 attackerBalance = _asset.balanceOf(attacker);
        // assertLe(
        //   attackerBalance,
        //   attackerInitialAmount,
        //   "Attacker didn't make a profit"
        // );

        // // attacker has made more profit than the user, cannot withdraw all funds, using preview
        // uint256 userBalance = _lendingAssetVault.previewRedeem(
        //   _lendingAssetVault.balanceOf(user)
        // );
        // assertLe(attackerBalance, userBalance, "Attacker didn't make more profit");
    }

    // function test_depositInflationAttack() public {
    //   // Setup attacker
    //   address attacker = makeAddr('attacker');
    //   deal(address(_asset), attacker, 100e18);
    //   vm.prank(attacker);
    //   _asset.approve(address(_lendingAssetVault), 100e18);

    //   // Setup victim
    //   address victim = makeAddr('victim');
    //   deal(address(_asset), victim, 100e18);
    //   vm.prank(victim);
    //   _asset.approve(address(_lendingAssetVault), 100e18);

    //   // Attacker is first to deposit a minimum amount of tokens
    //   vm.startPrank(attacker);
    //   _lendingAssetVault.deposit(1, attacker);
    //   assertEq(
    //     _lendingAssetVault.totalSupply(),
    //     _lendingAssetVault.balanceOf(attacker)
    //   );

    //   // Hypothesize the attacker is frontrunning the victim's deposit
    //   _lendingAssetVault.deposit(10e18,address(0xdead));
    //   vm.stopPrank();

    //   // Attacker holds all vault shares
    //   assertNotEq(
    //     _lendingAssetVault.totalSupply(),
    //     _lendingAssetVault.balanceOf(attacker),
    //     'Attacker has all the shares before victim deposits'
    //   );

    //   // Victim deposits an arbitrary amount of tokens
    //   vm.startPrank(victim);
    //   vm.expectRevert();
    //   _lendingAssetVault.deposit(10e18, victim);
    //   assertEq(0, _lendingAssetVault.balanceOf(victim)); // reverted so no shares minted
    //   vm.stopPrank();

    //   // Attacker holds all vault shares
    //   assertEq(
    //     _lendingAssetVault.totalSupply(),
    //     _lendingAssetVault.balanceOf(attacker),
    //     'Attacker has all the shares since victim did not deposit'
    //   );

    //   // Attacker withdraws all vault shares
    //   uint256 attackerBalance = _asset.balanceOf(attacker);
    //   uint256 attackerShares = _lendingAssetVault.balanceOf(attacker);
    //   vm.prank(attacker);
    //   _lendingAssetVault.redeem(attackerShares, attacker, attacker);

    //   assertEq(
    //     _asset.balanceOf(attacker) - attackerBalance,
    //     10e18 + 1,
    //     'Attacker should not get his tokens back + victims tokens'
    //   );
    // }

    function test_vaultMaxWithdraw() public {
        address[] memory _tvs = new address[](1);
        uint256[] memory _ps = new uint256[](1);
        _tvs[0] = address(_testVault);
        _ps[0] = 10e18;
        _lendingAssetVault.setVaultMaxAllocation(_tvs, _ps);

        uint256 _lavDepAmt = 10e18;
        uint256 _extDepAmt = _lavDepAmt / 2;
        _lendingAssetVault.deposit(_lavDepAmt, address(this));
        assertEq(_lendingAssetVault.totalSupply(), _lavDepAmt);

        uint256 maxWithdraw = _lendingAssetVault.maxWithdraw(address(this));
        uint256 balanceInVault = _asset.balanceOf(address(_lendingAssetVault));
        assertEq(maxWithdraw, balanceInVault);

        _testVault.depositFromLendingAssetVault(address(_lendingAssetVault), _extDepAmt);

        maxWithdraw = _lendingAssetVault.maxWithdraw(address(this));
        balanceInVault = _asset.balanceOf(address(_lendingAssetVault));
        assertEq(maxWithdraw, balanceInVault);

        // should not revert
        vm.roll(block.timestamp + 1);
        _lendingAssetVault.withdraw(maxWithdraw, address(this), address(this));
    }

    function test_previewMint_NoWhitelistedVaults() public {
        // Remove whitelisted vault
        _lendingAssetVault.setVaultWhitelist(address(_testVault), false);

        // Initial deposit to set totalSupply and totalAssets
        uint256 initialDeposit = 10e18;
        _lendingAssetVault.deposit(initialDeposit, address(this));

        // Preview minting shares
        uint256 sharesToMint = 5e18;
        uint256 assetsNeeded = _lendingAssetVault.previewMint(sharesToMint);

        // Since there are no whitelisted vaults, previewMint should be a simple calculation
        // based on current totalSupply and totalAssets
        uint256 expectedAssets = (sharesToMint * _lendingAssetVault.totalAssets()) / _lendingAssetVault.totalSupply();
        assertEq(assetsNeeded, expectedAssets, "Preview mint calculation incorrect without whitelisted vaults");

        // Verify by actually minting
        uint256 actualAssets = _lendingAssetVault.mint(sharesToMint, address(this));
        assertEq(actualAssets, assetsNeeded, "Actual mint differs from preview");
    }

    // function test_previewMint_WithWhitelistedVaultAndInterest() public {
    //     // Setup vault allocation
    //     address[] memory vaults = new address[](1);
    //     vaults[0] = address(_testVault);
    //     uint256[] memory percentages = new uint256[](1);
    //     percentages[0] = 10e18;
    //     _lendingAssetVault.setVaultMaxAllocation(vaults, percentages);

    //     // Initial deposit
    //     uint256 initialDeposit = 10e18;
    //     _lendingAssetVault.deposit(initialDeposit, address(this));

    //     // Deposit half to whitelisted vault
    //     uint256 vaultDeposit = initialDeposit / 2;
    //     _testVault.depositFromLendingAssetVault(address(_lendingAssetVault), vaultDeposit);

    //     // Simulate interest accrual in the vault
    //     uint256 interest = 1e18;
    //     _testVault.simulateInterestAccrual(interest);

    //     // Advance time to trigger interest calculation
    //     vm.warp(block.timestamp + 1 days);

    //     // Get preview of interest that would be added
    //     (uint256 interestEarned,,,,,) = _testVault.previewAddInterest();
    //     assertGt(interestEarned, 0, "Interest should be earned");

    //     // Preview minting shares
    //     uint256 sharesToMint = 5e18;
    //     uint256 assetsNeeded = _lendingAssetVault.previewMint(sharesToMint);

    //     // The preview should account for the increased value from interest
    //     uint256 preInterestAssets = (sharesToMint * initialDeposit) / _lendingAssetVault.totalSupply();
    //     assertGt(assetsNeeded, preInterestAssets, "Preview mint should account for accrued interest");

    //     // Calculate expected assets needed with interest
    //     uint256 expectedAssetsWithInterest =
    //         (sharesToMint * (initialDeposit + interestEarned)) / _lendingAssetVault.totalSupply();
    //     assertEq(assetsNeeded, expectedAssetsWithInterest, "Preview mint calculation incorrect with interest");

    //     // Verify by actually minting
    //     uint256 actualAssets = _lendingAssetVault.mint(sharesToMint, address(this));
    //     assertEq(actualAssets, assetsNeeded, "Actual mint differs from preview");
    // }

    function test_previewMint_ZeroTotalSupply() public {
        // No deposits yet, so totalSupply is 0
        uint256 sharesToMint = 10e18;
        uint256 assetsNeeded = _lendingAssetVault.previewMint(sharesToMint);

        // When totalSupply is 0, 1 share should equal 1 asset (PRECISION)
        assertEq(assetsNeeded, sharesToMint, "Preview mint with zero total supply should return same amount");

        // Verify by actually minting
        uint256 actualAssets = _lendingAssetVault.mint(sharesToMint, address(this));
        assertEq(actualAssets, assetsNeeded, "Actual mint differs from preview");
    }
}

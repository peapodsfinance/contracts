// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from 'forge-std/Test.sol';
import '../contracts/test/TestERC20.sol';
import '../contracts/test/TestERC4626Vault.sol';
import '../contracts/LendingAssetVault.sol';
import 'forge-std/console.sol';

contract LendingAssetVaultTest is Test {
  TestERC20 _asset;
  TestERC4626Vault _testVault;
  LendingAssetVault _lendingAssetVault;

  function setUp() public {
    _asset = new TestERC20('Test Token', 'tTEST');
    _testVault = new TestERC4626Vault(address(_asset));
    _lendingAssetVault = new LendingAssetVault(
      'Test LAV',
      'tLAV',
      address(_asset)
    );

    _asset.approve(address(_testVault), _asset.totalSupply());
    _asset.approve(address(_lendingAssetVault), _asset.totalSupply());
    _lendingAssetVault.setVaultWhitelist(address(_testVault), true);
  }

  function test_deposit() public {
    _lendingAssetVault.deposit(10e18, address(this));
    assertEq(
      _lendingAssetVault.totalSupply(),
      _lendingAssetVault.balanceOf(address(this))
    );
  }

  function test_withdrawNoCbrDiff() public {
    uint256 _depAmt = 10e18;
    _lendingAssetVault.deposit(_depAmt, address(this));
    assertEq(_lendingAssetVault.totalSupply(), _depAmt);
    _lendingAssetVault.withdraw(_depAmt / 2, address(this), address(0));
    assertEq(
      _lendingAssetVault.totalSupply(),
      _lendingAssetVault.balanceOf(address(this))
    );
    assertEq(
      _asset.balanceOf(address(this)),
      _asset.totalSupply() - _depAmt / 2
    );
  }

  function test_redeemNoCbrDiff() public {
    uint256 _depAmt = 10e18;
    _lendingAssetVault.deposit(_depAmt, address(this));
    assertEq(_lendingAssetVault.totalSupply(), _depAmt);
    _lendingAssetVault.redeem(_depAmt / 2, address(this), address(0));
    assertEq(
      _lendingAssetVault.totalSupply(),
      _lendingAssetVault.balanceOf(address(this))
    );
    assertEq(
      _asset.balanceOf(address(this)),
      _asset.totalSupply() - _depAmt / 2
    );
  }

  function test_withdrawCbrChange() public {
    uint256 _depAmt = 10e18;
    _lendingAssetVault.deposit(_depAmt, address(this));
    assertEq(_lendingAssetVault.totalSupply(), _depAmt);
    _lendingAssetVault.donate(_depAmt);
    _lendingAssetVault.withdraw(_depAmt / 2, address(this), address(0));
    assertEq(
      _lendingAssetVault.totalSupply(),
      _lendingAssetVault.balanceOf(address(this))
    );
    assertEq(
      _asset.balanceOf(address(this)),
      _asset.totalSupply() - ((3 * _depAmt) / 2)
    );
  }

  function test_redeemCbrChange() public {
    uint256 _depAmt = 10e18;
    _lendingAssetVault.deposit(_depAmt, address(this));
    assertEq(_lendingAssetVault.totalSupply(), _depAmt);
    _lendingAssetVault.donate(_depAmt);
    _lendingAssetVault.redeem(
      _lendingAssetVault.balanceOf(address(this)) / 4,
      address(this),
      address(0)
    );
    assertEq(
      _lendingAssetVault.totalSupply(),
      _lendingAssetVault.balanceOf(address(this))
    );
    assertEq(
      _asset.balanceOf(address(this)),
      _asset.totalSupply() - ((3 * _depAmt) / 2)
    );
  }

  function test_vaultDepositAndWithdrawNoCbrChange() public {
    address[] memory vaults = new address[](1);
    vaults[0] = address(_testVault);
    uint256[] memory percentages = new uint256[](1);
    percentages[0] = 10000;
    _lendingAssetVault.setVaultMaxPerc(vaults, percentages);

    uint256 _lavDepAmt = 10e18;
    uint256 _extDepAmt = _lavDepAmt / 2;
    _lendingAssetVault.deposit(_lavDepAmt, address(this));
    assertEq(_lendingAssetVault.totalSupply(), _lavDepAmt);

    _testVault.depositFromLendingAssetVault(
      address(_lendingAssetVault),
      _extDepAmt
    );
    _testVault.withdrawToLendingAssetVault(
      address(_lendingAssetVault),
      _extDepAmt
    );

    _lendingAssetVault.withdraw(_lavDepAmt / 2, address(this), address(0));
    assertEq(
      _lendingAssetVault.totalSupply(),
      _lendingAssetVault.balanceOf(address(this))
    );
    assertEq(
      _asset.balanceOf(address(this)),
      _asset.totalSupply() - _lavDepAmt / 2
    );
  }

  function test_vaultDepositAndWithdrawWithCbrChange() public {
    address[] memory vaults = new address[](1);
    vaults[0] = address(_testVault);
    uint256[] memory percentages = new uint256[](1);
    percentages[0] = 10000;
    _lendingAssetVault.setVaultMaxPerc(vaults, percentages);

    uint256 _lavDepAmt = 10e18;
    uint256 _extDepAmt = _lavDepAmt / 2;
    _lendingAssetVault.deposit(_lavDepAmt, address(this));
    assertEq(_lendingAssetVault.totalSupply(), _lavDepAmt);

    _testVault.depositFromLendingAssetVault(
      address(_lendingAssetVault),
      _extDepAmt
    );
    _asset.transfer(address(_testVault), _extDepAmt);
    _testVault.withdrawToLendingAssetVault(
      address(_lendingAssetVault),
      _extDepAmt
    );

    _lendingAssetVault.withdraw(_lavDepAmt / 2, address(this), address(0));

    uint256 _optimalBal = _asset.totalSupply() - _lavDepAmt / 2 - _extDepAmt;
    console.log(
      'actual bal: %s -- optimal bal: %s',
      _asset.balanceOf(address(this)),
      _optimalBal
    );
    assertApproxEqAbs(_asset.balanceOf(address(this)), _optimalBal, 1e18);

    _testVault.withdrawToLendingAssetVault(
      address(_lendingAssetVault),
      _lendingAssetVault.vaultUtilization(address(_testVault))
    );
    assertEq(_lendingAssetVault.vaultUtilization(address(_testVault)), 0);
    assertApproxEqAbs(_lendingAssetVault.totalAssets(), _lavDepAmt, 1e2);
  }

  function test_redeemFromVaultAll() public {
    uint256 _lavDepAmt = 10e18;
    uint256 _extDepAmt = _lavDepAmt / 2;
    _lendingAssetVault.deposit(_lavDepAmt, address(this));
    address[] memory vaults = new address[](1);
    vaults[0] = address(_testVault);
    uint256[] memory percentages = new uint256[](1);
    percentages[0] = 10000;
    _lendingAssetVault.setVaultMaxPerc(vaults, percentages);

    _testVault.depositFromLendingAssetVault(
      address(_lendingAssetVault),
      _extDepAmt
    );

    uint256 _initialTotalAssetsUtilized = _lendingAssetVault.totalAssets() -
      _lendingAssetVault.totalAvailableAssets();

    vm.expectEmit(true, true, true, true);
    // emit ILendingAssetVault.RedeemFromVault(
    //   address(_testVault),
    //   _testVault.balanceOf(address(_lendingAssetVault)),
    //   _extDepAmt
    // );

    _lendingAssetVault.redeemFromVault(address(_testVault), 0);

    assertEq(_lendingAssetVault.vaultUtilization(address(_testVault)), 0);
    assertEq(
      _lendingAssetVault.totalAssets() -
        _lendingAssetVault.totalAvailableAssets(),
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
    percentages[0] = 10000;
    _lendingAssetVault.setVaultMaxPerc(vaults, percentages);

    _testVault.depositFromLendingAssetVault(
      address(_lendingAssetVault),
      _extDepAmt
    );

    uint256 _redeemShares = _testVault.balanceOf(address(_lendingAssetVault)) /
      2;
    uint256 _expectedAssets = _testVault.convertToAssets(_redeemShares);

    uint256 _initialVaultUtilization = _lendingAssetVault.vaultUtilization(
      address(_testVault)
    );
    uint256 _initialTotalAssetsUtilized = _lendingAssetVault.totalAssets() -
      _lendingAssetVault.totalAvailableAssets();

    vm.expectEmit(true, true, true, true);
    // emit ILendingAssetVault.RedeemFromVault(
    //   address(_testVault),
    //   _redeemShares,
    //   _expectedAssets
    // );

    _lendingAssetVault.redeemFromVault(address(_testVault), _redeemShares);

    assertEq(
      _lendingAssetVault.vaultUtilization(address(_testVault)),
      _initialVaultUtilization - _expectedAssets
    );
    assertEq(
      _lendingAssetVault.totalAssets() -
        _lendingAssetVault.totalAvailableAssets(),
      _initialTotalAssetsUtilized - _expectedAssets
    );
    assertEq(
      _asset.balanceOf(address(_lendingAssetVault)),
      _lavDepAmt - _extDepAmt + _expectedAssets
    );
  }

  function test_redeemFromVaultZeroShares() public {
    uint256 _lavDepAmt = 10e18;
    uint256 _extDepAmt = _lavDepAmt / 2;
    _lendingAssetVault.deposit(_lavDepAmt, address(this));
    address[] memory vaults = new address[](1);
    vaults[0] = address(_testVault);
    uint256[] memory percentages = new uint256[](1);
    percentages[0] = 10000;
    _lendingAssetVault.setVaultMaxPerc(vaults, percentages);

    _testVault.depositFromLendingAssetVault(
      address(_lendingAssetVault),
      _extDepAmt
    );

    uint256 _initialTotalAssetsUtilized = _lendingAssetVault.totalAssets() -
      _lendingAssetVault.totalAvailableAssets();

    uint256 _expectedShares = _testVault.balanceOf(address(_lendingAssetVault));
    uint256 _expectedAssets = _testVault.convertToAssets(_expectedShares);

    vm.expectEmit(true, true, true, true);
    // emit ILendingAssetVault.RedeemFromVault(
    //   address(_testVault),
    //   _expectedShares,
    //   _expectedAssets
    // );

    _lendingAssetVault.redeemFromVault(address(_testVault), 0);

    assertEq(_lendingAssetVault.vaultUtilization(address(_testVault)), 0);
    assertEq(
      _lendingAssetVault.totalAssets() -
        _lendingAssetVault.totalAvailableAssets(),
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
    percentages[0] = 10000;
    _lendingAssetVault.setVaultMaxPerc(vaults, percentages);

    _testVault.depositFromLendingAssetVault(
      address(_lendingAssetVault),
      _extDepAmt
    );

    uint256 _availableShares = _testVault.balanceOf(
      address(_lendingAssetVault)
    );
    uint256 _moreThanAvailable = _availableShares + 1e18;

    vm.expectRevert();
    _lendingAssetVault.redeemFromVault(address(_testVault), _moreThanAvailable);
  }
}

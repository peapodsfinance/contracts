# Peapods-Suite README

# Overview

Peapods engaged Guardian Audits for an in-depth security review of their LVF system. This comprehensive evaluation, conducted from September 9th to October 3rd, 2024, included the development of a specialized fuzzing suite to uncover complex logical errors in various protocol states. This suite, an integral part of the audit, was created during the review period and successfully delivered upon the audit's conclusion.

# Contents

The fuzzing suite primarily targets the core functionality found in `AutoCompoundingPodLp.sol`, `LeverageManager.sol` and `LendingAssetVault.sol`.

All of the invariants reside in the following contracts:
* AutoCompoundingPodLpHandler.sol
* PodHandler.sol
* LeverageManagerHandler.sol
* StakingPoolHandler.sol
* LendingAssetVaultHandler.sol
* FraxlendPairHandler.sol

## Source code changes to go deeper in testing

**LendingAssetVault.sol**
```diff
interface IVaultInterestUpdate {
-  function addInterest() external;
+  function addInterest(bool) external;
}
```

```diff
  /// @notice Updates interest and metadata for all whitelisted vaults
  /// @param _vaultToExclude Address of the vault to exclude from the update
  function _updateInterestAndMdInAllVaults(address _vaultToExclude) internal {
    if (!_updateInterestOnVaults) {
      return;
    }
    for (uint256 _i; _i < _vaultWhitelistAry.length; _i++) {
      address _vault = _vaultWhitelistAry[_i];
      if (_vault == _vaultToExclude) {
        continue;
      }
-      IVaultInterestUpdate(_vault).addInterest();
+      IVaultInterestUpdate(_vault).addInterest(false);
      _updateAssetMetadataFromVault(_vault);
    }
  }
```

**TokenRewards.sol**
```diff
function _distributeReward(address _wallet) internal {
    if (shares[_wallet] == 0) {
      return;
    }
    for (uint256 _i; _i < _allRewardsTokens.length; _i++) {
      address _token = _allRewardsTokens[_i];
      uint256 _amount = getUnpaid(_token, _wallet);
      rewards[_token][_wallet].realized += _amount;
      rewards[_token][_wallet].excluded = _cumulativeRewards(
        _token,
        shares[_wallet],
+        Math.Rounding.Up
      );
      if (_amount > 0) {
        rewardsDistributed[_token] += _amount;
        IERC20(_token).safeTransfer(_wallet, _amount);
        emit DistributeReward(_wallet, _token, _amount);
      }
    }
  }
```

```diff
function _resetExcluded(address _wallet) internal {
    for (uint256 _i; _i < _allRewardsTokens.length; _i++) {
      address _token = _allRewardsTokens[_i];
      rewards[_token][_wallet].excluded = _cumulativeRewards(
        _token,
        shares[_wallet],
+        Math.Rounding.Up
      );
    }
  }
```

```diff
function getUnpaid(
    address _token,
    address _wallet
  ) public view returns (uint256) {
    if (shares[_wallet] == 0) {
      return 0;
    }
-    uint256 earnedRewards = _cumulativeRewards(_token, shares[_wallet]);
+    uint256 earnedRewards = _cumulativeRewards(_token, shares[_wallet], Math.Rounding.Down);
    uint256 rewardsExcluded = rewards[_token][_wallet].excluded;
    if (earnedRewards <= rewardsExcluded) {
      return 0;
    }
    return earnedRewards - rewardsExcluded;
  }
```

```diff
function _cumulativeRewards(
    address _token,
    uint256 _share,
+    Math.Rounding rounding
  ) internal view returns (uint256) {

-    return (_share * _rewardsPerShare[_token]) / PRECISION;
+    return Math.mulDiv(_share, _rewardsPerShare[_token], PRECISION, rounding);
  }
```

## Setup and Run Instructions

1. Install Echidna, following the steps here: [Installation Guide](https://github.com/crytic/echidna#installation)
```shell
# Verify Installation
echidna --version
```

2. Install dependencies
```shell
forge install
yarn
yarn add @chainlink/contracts
```
3. Run Echidna

```shell
echidna test/invariant/PeapodsInvariant.sol --contract PeapodsInvariant --config test/invariant/echidna.yaml
```

To run (disabling Slither): 
```shell
PATH=./test/invariant/:$PATH echidna test/invariant/PeapodsInvariant.sol --contract PeapodsInvariant --config test/invariant/echidna.yaml
```

# Invariants
| **Invariant ID** | **Invariant Description** | **Passed** | **Remediation** | **Run Count** |
|:--------------:|:-----|:-----------:|:-----------:|:-----------:|
| **POD-01** | Insert description here | PASS |  | 10m+
| **POD-1** |	LeverageManager::_acquireBorrowTokenForRepayment should never Uniswap revert	| ❌ |  | 10m+
| **POD-2** |	LendingAssetVault::deposit/mint share balance of receiver should increase	| ❌ |  | 10m+
| **POD-3** |	LendingAssetVault::withdraw/redeem share balance of user should decrease	| ✅ |  | 10m+ 
| **POD-4** |	vaultUtilization[_vault] == FraxLend.convertToAssets(LAV shares) post-update	| ❌ |  | 10m+
| **POD-5** |	LendingAssetVault::totalAssetsUtilized totalAssetsUtilized == sum(all vault utilizations)	| ✅ |  | 10m+ 
| **POD-6** |	LendingAssetVault::whitelistDeposit totalAvailableAssets() should increase	| ✅ |  | 10m+
| **POD-7** |	LendingAssetVault::whitelistDeposit vault utilization should decrease accurately	| ❌ |  | 10m+
| **POD-8** |	LendingAssetVault::whitelistDeposit total utilization should decrease accurately	| ❌ |  | 10m+
| **POD-9** |	LendingAssetVault::whitelistWithdraw totalAvailableAssets() should decrease	| ✅ |  | 10m+
| **POD-10** |	LendingAssetVault::whitelistWithdraw vault utilization should increase accurately	| ✅ |  | 10m+
| **POD-11** |	LendingAssetVault::whitelistWithdraw total utilization should increase accurately	| ✅ |  | 10m+
| **POD-12** |	LendingAssetVault::global total assets == sum(deposits + donations + interest accrued - withdrawals)	| ❌ |  | 10m+
| **POD-13** |	LendingAssetVault::withdraw/redeem User can't withdraw more than their share of total assets	| ❌ |  | 10m+
| **POD-14a** |	LendingAssetVault::donate Post-donation shares shouldn't have increased, but totalAssets should have by donated amount	| ❌ |  | 10m+
| **POD-14b** |	LendingAssetVault::donate Post-donation shares shouldn't have increased, but totalAssets should have by donated amount	| ✅ |  | 10m+
| **POD-15** |	LendingAssetVault::global FraxLend vault should never more assets lent to it from the LAV that the allotted _vaultMaxPerc	| ✅ |  | 10m+
| **POD-16** |	LendingAssetVault::whitelistDeposit Post-state utilization rate in FraxLend should have decreased (called by repayAsset in FraxLend) (utilization rate retrieved from currentRateInfo public var)	| ✅ |  | 10m+
| **POD-17** |	LendingAssetVault::whitelistWithdraw Post-state utilization rate in FraxLend should have increased or not changed (if called within from a redeem no change, increase if called from borrowAsset)	| ✅ |  | 10m+
| **POD-18a** |	LeverageManager::addLeverage Post adding leverage, there totalBorrow amount and shares, as well as utilization should increase in Fraxlend	| ✅ |  | 10m+
| **POD-18b** |	LeverageManager::addLeverage Post adding leverage, there totalBorrow amount and shares, as well as utilization should increase in Fraxlend	| ✅ |  | 10m+
| **POD-19a** |	LeverageManager::removeLeverage Post removing leverage, there totalBorrow amount and shares, as well as utilization should decrease in Fraxlend	| ✅ |  | 10m+
| **POD-19b** |	LeverageManager::removeLeverage Post removing leverage, there totalBorrow amount and shares, as well as utilization should decrease in Fraxlend	| ✅ |  | 10m+
| **POD-20** |	Post adding leverage, there should be a higher supply of spTKNs (StakingPoolToken)	| ✅ |  | 10m+
| **POD-21** |	Post adding leverage, there should be a higher supply of aspTKNs (AutoCompoundingPodLp)	| ✅ |  | 10m+
| **POD-22** |	Post adding leverage, the custodian for the position should have a higher userCollateralBalance	| ✅ |  | 10m+
| **POD-23** |	Post removing leverage, there should be a lower supply of spTKNs (StakingPoolToken)	| ❌ |  | 10m+
| **POD-24** |	Post removing leverage, there should be a lower supply of aspTKNs (AutoCompoundingPodLp)	| ✅ |  | 10m+
| **POD-25** |	Post removing leverage, the custodian for the position should have a lower userCollateralBalance	| ✅ |  | 10m+
| **POD-26** |	FraxLend: cbr change with one large update == cbr change with multiple, smaller updates	| ❌ |  | 10m+
| **POD-27** |	LeverageManager contract should never hold any token balances	| ✅ |  | 10m+
| **POD-28** |	FraxlendPair.totalAsset should be greater or equal to vaultUtilization (LendingAssetVault)	| ✅ |  | 10m+
| **POD-29** |	LendingAssetVault::global totalAssets must be greater than totalAssetUtilized”	| ✅ |  | 10m+
| **POD-30** |	repayAsset should not lead to to insolvency	| ✅ |  | 10m+
| **POD-31** |	staking pool balance should equal token reward shares	| ✅ |  | 10m+
| **POD-32** |	FraxLend: (totalBorrow.amount) / totalAsset.totalAmount(address(externalAssetVault)) should never be more than 100%	| ✅ |  | 10m+
| **POD-33** |	FraxLend: totalAsset.totalAmount(address(0)) == 0 -> totalBorrow.amount == 0	| ✅ |  | 10m+
| **POD-34** |	AutoCompoundingPodLP: mint() should increase asp supply by exactly that amount of shares	| ✅ |  | 10m+
| **POD-35** |	AutoCompoundingPodLP: deposit() should decrease user balance of sp tokens by exact amount of assets passed	| ✅ |  | 10m+
| **POD-36** |	AutoCompoundingPodLP: redeem() should decrease asp supply by exactly that amount of shares	| ✅ |  | 10m+
| **POD-37** |	AutoCompoundingPodLP: withdraw() should increase user balance of sp tokens by exact amount of assets passed	| ✅ |  | 10m+
| **POD-38** |	AutoCompoundingPodLP: mint/deposit/redeem/withdraw()  spToken total supply should never decrease	| ✅ |  | 10m+
| **POD-39** |	AutoCompounding should not revert with Insufficient Amount	| ❌ |  | 10m+
| **POD-40** |	AutoCompounding should not revert with Insufficient Liquidity	| ❌ |  | 10m+
| **POD-41** |	AutoCompoundingPodLP: redeem/withdraw() should never get an InsufficientBalance or underflow/overflow revert	| ✅ |  | 10m+
| **POD-42** |	custodian position is solvent after adding leverage and removing leverage	| ✅ |  | 10m+
| **POD-43** |	TokenReward: global:  getUnpaid() <= balanceOf reward token	| ✅ |  | 10m+
| **POD-44** |	LVF: global there should not be any remaining allowances after each function call	| ✅ |  | 10m+

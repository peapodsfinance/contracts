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

/// Was getting underflows with `_basePerSpTkn18 == 0`
**spTKNMinimalOracle.sol**
```diff
function _calculateSpTknPerBase(
    uint256 _price18
  ) internal view returns (uint256 _spTknBasePrice18) {
    uint256 _priceBasePerPTkn18 = _calculateBasePerPTkn(_price18);
    address _pair = _getPair();

    (uint112 _reserve0, uint112 _reserve1) = V2_RESERVES.getReserves(_pair);
    uint256 _k = uint256(_reserve0) * _reserve1;
    uint256 _kDec = 10 **
      IERC20Metadata(IUniswapV2Pair(_pair).token0()).decimals() *
      10 ** IERC20Metadata(IUniswapV2Pair(_pair).token1()).decimals();
    uint256 _avgBaseAssetInLp18 = _sqrt((_priceBasePerPTkn18 * _k) / _kDec) *
      10 ** (18 / 2);
    uint256 _basePerSpTkn18 = (2 *
      _avgBaseAssetInLp18 *
      10 ** IERC20Metadata(_pair).decimals()) / IERC20(_pair).totalSupply();
+      if (_basePerSpTkn18 == 0) return 1e18;
    _spTknBasePrice18 = 10 ** (18 * 2) / _basePerSpTkn18;

    // if the base asset is a pod, we will assume that the CL/chainlink pool(s) are
    // pricing the underlying asset of the base asset pod, and therefore we will
    // adjust the output price by CBR and unwrap fee for this pod for more accuracy and
    // better handling accounting for liquidation path
    if (BASE_IS_POD) {
      _spTknBasePrice18 = _checkAndHandleBaseTokenPodConfig(_spTknBasePrice18);
    }
  }
```

/// Was getting underflows caused by `aspTKNMinimalOracle::getPrices` returning 0 for _priceLow & _priceHigh
**aspTKNMinimalOracle.sol**
```diff
function getPrices()
    public
    view
    virtual
    override
    returns (bool _isBadData, uint256 _priceLow, uint256 _priceHigh)
  {
    uint256 _assetFactor = 10 ** 18;
    uint256 _aspTknPerSpTkn = IERC4626(ASP_TKN).convertToShares(_assetFactor);
    (_isBadData, _priceLow, _priceHigh) = super.getPrices();
    if (_priceLow == 0 && _priceHigh == 0) assert(false);
    _priceLow = (_priceLow * _aspTknPerSpTkn) / _assetFactor;
    _priceHigh = (_priceHigh * _aspTknPerSpTkn) / _assetFactor;
+    if (_priceLow == 0) _priceLow = 1e18;
+    if (_priceHigh == 0) _priceHigh = 1e18;
  }
```

/// Updated `_getSwapAmount`
```diff
  function _getSwapAmt(
    address _t0,
    address _t1,
    address _swapT,
    uint256 _fullAmt
  ) internal returns (uint256) {
    (uint112 _r0, uint112 _r1) = DEX_ADAPTER.getReserves(
      DEX_ADAPTER.getV2Pool(_t0, _t1)
    );
    uint112 _r = _swapT == _t0 ? _r0 : _r1;
    emit Message112("_r", _r);
    emit MessageUint("fullAmt", _fullAmt);
    emit MessageUint("_sqrt(_fullAmt * (_r * 3988000 + _fullAmt * 3988009))", _sqrt(_fullAmt * (_r * 3988000 + _fullAmt * 3988009)));
    emit MessageUint("(_fullAmt * 1997)) / 1994", (_fullAmt * 1997) / 1994);
+    return (_sqrt(_r * (_r * 3988009 + _fullAmt * 3988000)) - _r * 1997) / 1994;
-    // return
-    //   (_sqrt(_fullAmt * (_r * 3988000 + _fullAmt * 3988009)) -
-    //     (_fullAmt * 1997)) / 1994;
  }
```

## Setup and Run Instructions

**A note about deployment. All contracts that are etched need to have their creation bytecode replaced in the echidna.yaml if changes have been made**

**Also, if you see `if (getPanicCode(err) == 17) return;` there is an underflow panic happening, if you'd like to see it uncomment!**

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
| **POD-1** |	LeverageManager::_acquireBorrowTokenForRepayment should never Uniswap revert	| ❌ | ❌ | 10m+
| **POD-2** |	LendingAssetVault::deposit/mint share balance of receiver should increase	| ❌ | ❌ | 10m+
| **POD-3** |	LendingAssetVault::withdraw/redeem share balance of user should decrease	| ✅ | ✅ | 10m+ 
| **POD-4** |	vaultUtilization[_vault] == FraxLend.convertToAssets(LAV shares) post-update	| ❌ | ❌ | 10m+
| **POD-5** |	LendingAssetVault::totalAssetsUtilized totalAssetsUtilized == sum(all vault utilizations)	| ✅ | ✅ | 10m+ 
| **POD-6** |	LendingAssetVault::whitelistDeposit totalAvailableAssets() should increase	| ✅ | ✅ | 10m+
| **POD-7** |	LendingAssetVault::whitelistDeposit vault utilization should decrease accurately	| ❌ | ❌ | 10m+
| **POD-8** |	LendingAssetVault::whitelistDeposit total utilization should decrease accurately	| ❌ | ❌ | 10m+
| **POD-9** |	LendingAssetVault::whitelistWithdraw totalAvailableAssets() should decrease	| ✅ | ✅ | 10m+
| **POD-10** |	LendingAssetVault::whitelistWithdraw vault utilization should increase accurately	| ✅ | ✅ | 10m+
| **POD-11** |	LendingAssetVault::whitelistWithdraw total utilization should increase accurately	| ✅ | ✅ | 10m+
| **POD-12** |	LendingAssetVault::global total assets == sum(deposits + donations + interest accrued - withdrawals)	| ❌ | ❌ | 10m+
| **POD-13** |	LendingAssetVault::withdraw/redeem User can't withdraw more than their share of total assets	| ❌ | ✅ | 10m+
| **POD-14a** |	LendingAssetVault::donate Post-donation shares shouldn't have increased, but totalAssets should have by donated amount	| ❌ | ✅ | 10m+
| **POD-14b** |	LendingAssetVault::donate Post-donation shares shouldn't have increased, but totalAssets should have by donated amount	| ✅ | ✅ | 10m+
| **POD-15** |	LendingAssetVault::global FraxLend vault should never more assets lent to it from the LAV that the allotted _vaultMaxPerc	| ✅ | ✅ | 10m+
| **POD-16** |	LendingAssetVault::whitelistDeposit Post-state utilization rate in FraxLend should have decreased (called by repayAsset in FraxLend) (utilization rate retrieved from currentRateInfo public var)	| ✅ | ✅ | 10m+
| **POD-17** |	LendingAssetVault::whitelistWithdraw Post-state utilization rate in FraxLend should have increased or not changed (if called within from a redeem no change, increase if called from borrowAsset)	| ✅ | ✅ | 10m+
| **POD-18a** |	LeverageManager::addLeverage Post adding leverage, there totalBorrow amount and shares, as well as utilization should increase in Fraxlend	| ✅ | ✅ | 10m+
| **POD-18b** |	LeverageManager::addLeverage Post adding leverage, there totalBorrow amount and shares, as well as utilization should increase in Fraxlend	| ✅ | ✅ | 10m+
| **POD-19a** |	LeverageManager::removeLeverage Post removing leverage, there totalBorrow amount and shares, as well as utilization should decrease in Fraxlend	| ✅ | ✅ | 10m+
| **POD-19b** |	LeverageManager::removeLeverage Post removing leverage, there totalBorrow amount and shares, as well as utilization should decrease in Fraxlend	| ✅ | ✅ | 10m+
| **POD-20** |	Post adding leverage, there should be a higher supply of spTKNs (StakingPoolToken)	| ✅ | ✅ | 10m+
| **POD-21** |	Post adding leverage, there should be a higher supply of aspTKNs (AutoCompoundingPodLp)	| ✅ | ✅ | 10m+
| **POD-22** |	Post adding leverage, the custodian for the position should have a higher userCollateralBalance	| ✅ | ✅ | 10m+
| **POD-23** |	Post removing leverage, there should be a lower supply of spTKNs (StakingPoolToken)	| ❌ | ❌ | 10m+
| **POD-24** |	Post removing leverage, there should be a lower supply of aspTKNs (AutoCompoundingPodLp)	| ✅ | ✅ | 10m+
| **POD-25** |	Post removing leverage, the custodian for the position should have a lower userCollateralBalance	| ✅ | ✅ | 10m+
| **POD-26** |	FraxLend: cbr change with one large update == cbr change with multiple, smaller updates	| ❌ | ❌ | 10m+
| **POD-27** |	LeverageManager contract should never hold any token balances	| ✅ | ✅ | 10m+
| **POD-28** |	FraxlendPair.totalAsset should be greater or equal to vaultUtilization (LendingAssetVault)	| ✅ | ✅ | 10m+
| **POD-29** |	LendingAssetVault::global totalAssets must be greater than totalAssetUtilized”	| ✅ | ✅ | 10m+
| **POD-30** |	repayAsset should not lead to to insolvency	| ✅ | ✅ | 10m+
| **POD-31** |	staking pool balance should equal token reward shares	| ✅ | ✅ | 10m+
| **POD-32** |	FraxLend: (totalBorrow.amount) / totalAsset.totalAmount(address(externalAssetVault)) should never be more than 100%	| ✅ | ✅ | 10m+
| **POD-33** |	FraxLend: totalAsset.totalAmount(address(0)) == 0 -> totalBorrow.amount == 0	| ✅ | ✅ | 10m+
| **POD-34** |	AutoCompoundingPodLP: mint() should increase asp supply by exactly that amount of shares	| ✅ | ✅ | 10m+
| **POD-35** |	AutoCompoundingPodLP: deposit() should decrease user balance of sp tokens by exact amount of assets passed	| ✅ | ✅ | 10m+
| **POD-36** |	AutoCompoundingPodLP: redeem() should decrease asp supply by exactly that amount of shares	| ✅ | ✅ | 10m+
| **POD-37** |	AutoCompoundingPodLP: withdraw() should increase user balance of sp tokens by exact amount of assets passed	| ✅ | ✅ | 10m+
| **POD-38** |	AutoCompoundingPodLP: mint/deposit/redeem/withdraw()  spToken total supply should never decrease	| ✅ | ✅ | 10m+
| **POD-39** |	AutoCompounding should not revert with Insufficient Amount	| ❌ | ❌ | 10m+
| **POD-40** |	AutoCompounding should not revert with Insufficient Liquidity	| ❌ | ❌ | 10m+
| **POD-41** |	AutoCompoundingPodLP: redeem/withdraw() should never get an InsufficientBalance or underflow/overflow revert	| ✅ | ✅ | 10m+
| **POD-42** |	custodian position is solvent after adding leverage and removing leverage	| ✅ | ✅ | 10m+
| **POD-43** |	TokenReward: global:  getUnpaid() <= balanceOf reward token	| ✅ | ✅ | 10m+
| **POD-44** |	LVF: global there should not be any remaining allowances after each function call	| ✅ | ✅ | 10m+

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

LendingAssetVault.sol
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

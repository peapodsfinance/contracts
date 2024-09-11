# Peapods-Suite README

# Overview

INT DAO engaged Guardian Audits for an in-depth security review of their LVF system. This comprehensive evaluation, conducted from September 9th to October 3rd, 2024, included the development of a specialized fuzzing suite to uncover complex logical errors in various protocol states. This suite, an integral part of the audit, was created during the review period and successfully delivered upon the audit's conclusion.

# Contents

The fuzzing suite primarily targets the core functionality found in `BoostManager.sol`, `PickCallbackV2.sol` and `NftDistributorV2.sol`.

All of the invariants reside in the following contracts:
* BoostManagerHandler.sol
* GuidedInvariants.sol
* NftDistributorV2Handler.sol
* RewardDistributorHandler.sol
* RewardTokenHandler.sol
* V3PoolHandler.sol

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
| **INT-01** | If joinedTimestamp[tokenId] > 0, then tokenId BoostType.BASE balance > 0 | PASS |  | 10m+
| **INT-02** | block.timestamp - joinedTimestamp[tokenId] should never underflow. | PASS |  | 10m+
| **INT-03** | totalSupply == sum(stakes) | PASS |  | 10m+
| **INT-04** | multiMint should increase NFT total supply by length of tokenIds on success. | PASS |  | 10m+
| **INT-05** | multiBurn should decrease NFT total supply by length of tokenIds on success. | PASS |  | 10m+
| **INT-06** | If user NFT does not exist, calling sync should lead to BASE balance to be 0. | PASS |  | 10m+
| **INT-07** | If user NFT does exist, calling sync should lead to BASE balance to gt 0. | PASS |  | 10m+
| **INT-08** | After unstake is called on a specific BoostType, the balance boostInfo[id].balances[tokenId] should be 0. | PASS |  | 10m+
| **INT-09** | boostInfo[BoostType.BASE].balances[tokenId] should never be > TOKENS_PER_NFT after NftDistributor.mint or NftDistributor.mintForTicket | **FAIL** |  | 10m+
| **INT-10** | forceUnstake should not revert | PASS |  | 10m+
| **INT-11** | autoProcessedIndex should never be greater than or equal to tokenIds.length | PASS |  | 10m+
| **INT-12** | tokenId should not exist after forceUnstake | PASS |  | 10m+
| **INT-13** | autoProcessedIndex should always be strictly less than _tokenIds.length() | PASS |  | 10m+
| **INT-14** | If a set had tickets minted, that set should have a vrf result in vrfResultsBySet | PASS |  | 10m+
| **INT-15** | totalEarned should not exceed added rewards through addRewards | PASS |  | 10m+
| **INT-16** | view function totalEarned(pool) == gained after process | PASS |  | 10m+
| **INT-17** | If user unstakes then stakes their reward should be 0 for all pools. | PASS |  | 10m+
| **INT-18** | User should not be able to gain rewards that should have been forfeited | **FAIL** |  | 10m+
| **INT-19** | User should not be able to manipulate BASE balance | **FAIL** |  | 10m+
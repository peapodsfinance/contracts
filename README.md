# Peapods Finance (PEAS)

## Compile

```sh
$ npx hardhat compile
```

## Deploy (Foundry)

To deploy Peapods protocol in its entirety, follow these steps to execute Foundry scripts to stand up all contracts:

1. Deploy your protocol token, or `forge script script/DeployPEAS.s.sol --verify`
2. `forge script script/DeployPodBeacons.s.sol --verify`
3. Deploy core contracts, and add implementation & beacon env vars to set in pod factory, `forge script script/DeployCore.s.sol --verify`
4. `forge script script/DeployUniswapDexAdapter.s.sol --verify`
5. `forge script script/DeployVerificationPod.s.sol --verify`

### Deploy LVF on top of Peapods (Optional)

6. Deploy LendingAssetVault for pairedLpTkn `forge script script/DeployLendingAssetVault.s.sol`
7. Deploy LeverageManager `forge script script/DeployLeverageManager.s.sol`
8. Deploy necessary flash sources for supported pairedLpTkns `forge script script/DeployBalancerFlashSource.s.sol` and others
9. Deploy ChainlinkSinglePriceOracle, UniswapV3SinglePriceOracle, and optionally DIAOracleV2SinglePriceOracle `forge script sciprt/DeployAllSinglePriceOracles.s.sol`
10. Deploy VariableInterestRate.sol for fraxlend pair(s) (`DeployVIR.s.sol` foundry script in fraxlend repo)

### Turn on LVF for a pod (Optional)

11. Deploy aspTKN for pod `forge script script/DeployAutoCompoundingPodLp.s.sol`
12. Deploy aspTKN/pairedLpTkn oracle `forge script script/DeployAspTknMinimalOracle.s.sol`
13. Deploy FraxlendLendingPair.sol for aspTKN collateral, pairedLpTkn borrow token, aspTKN oracle
14. Set pod-specific info in LeverageManager `forge script script/SetPodLeverageManager.s.sol`

## Deploy (Legacy - Hardhat)

If your contract requires extra constructor arguments, you'll have to specify them in [deploy options](https://hardhat.org/plugins/hardhat-deploy.html#deployments-deploy-name-options).

```sh
$ CONTRACT_NAME=V3TwapUtilities npx hardhat run --network goerli scripts/deploy.js
$ CONTRACT_NAME=UniswapDexAdapter npx hardhat run --network goerli scripts/deploy.js
$ CONTRACT_NAME=ProtocolFees npx hardhat run --network goerli scripts/deploy.js
$ CONTRACT_NAME=ProtocolFeeRouter npx hardhat run --network goerli scripts/deploy.js
$ CONTRACT_NAME=PEAS npx hardhat run --network goerli scripts/deploy.js
$ # For PEAS: provide V3 1% LP in Uniswap paired with DAI, then update cardinality to support 5 min TWAP
$ CONTRACT_NAME=UnweightedIndex npx hardhat run --network goerli scripts/deploy.js
$ CONTRACT_NAME=IndexManager npx hardhat run --network goerli scripts/deploy.js
$ # For IndexManager: add indexes
$ CONTRACT_NAME=IndexUtils npx hardhat run --network goerli scripts/deploy.js
```

## Verify (Legacy - Hardhat)

```sh
$ npx hardhat verify CONTRACT_ADDRESS --network goerli
$ # or
$ npx hardhat verify --constructor-args arguments.js CONTRACT_ADDRESS
```

## Tests

We are building foundry/forge tests across the code base slowly, and as of now will leverage existing pods/contracts on mainnet so use --fork-url to a mainnet RPC when running tests.

See https://book.getfoundry.sh/reference/forge/forge-test for more info

```sh
$ # without verbosity of any kind
$ forge test --no-match-test invariant --fork-url https://eth.llamarpc.com
$ # show logs in tests
$ forge test -vv --no-match-test invariant --fork-url https://eth.llamarpc.com
$ # full trace of all calls
$ forge test -vvvv --no-match-test invariant --fork-url https://eth.llamarpc.com
```

## Flatten

You generally should not need to do this simply to verify in today's compiler version (0.8.x), but should you ever want to:

```sh
$ npx hardhat flatten {contract file location} > output.sol
```

## Leveraged Volatility Farming

### LendingAssetVault Setup & Testing

1. Deploy LendingAssetVault
2. Execute setVaultMaxAllocation for lending pair(s) we want to support
3. In lending pair(s), execute setExternalAssetVault for vault from #1
4. Deposit assets to lending asset vault in #1, and optionally into lending pair(s)

### Self-lending Setup & Testing

1. Deploy AutoCompoundingPodLpFactory
2. Get new AutoCompoundingPodLp CA via getNewCaFromParams in factory, pod == address(0)
3. Deploy Fraxlend LendingPair with CA from #2 as collateral token and underlying as borrow token
4. Deploy new pod with LendingPair CA from #3 as paired asset
5. Deposit a bit into new LendingPair from #3, wrap into pod from #4 and LP, then approve new spTKN of pod for factory in #1 to deposit minimum at aspTKN creation (#6)
6. Deploy AutoCompoundingPodLp (aspTKN) from factory in #1 with pod == address(0), then setPod in aspTKN to new pod from #5
7. In LeverageManager execute setLendingPair, and setFlashSource

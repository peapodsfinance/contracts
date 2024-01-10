# Peapods Finance (PEAS)

## Compile

```sh
$ npx hardhat compile
```

## Deploy

If your contract requires extra constructor arguments, you'll have to specify them in [deploy options](https://hardhat.org/plugins/hardhat-deploy.html#deployments-deploy-name-options).

```sh
$ CONTRACT_NAME=V3TwapUtilities npx hardhat run --network goerli scripts/deploy.js
$ CONTRACT_NAME=ProtocolFees npx hardhat run --network goerli scripts/deploy.js
$ CONTRACT_NAME=ProtocolFeeRouter npx hardhat run --network goerli scripts/deploy.js
$ CONTRACT_NAME=PEAS npx hardhat run --network goerli scripts/deploy.js
$ # For PEAS: provide V3 1% LP in Uniswap paired with DAI, then update cardinality to support 5 min TWAP
$ CONTRACT_NAME=UnweightedIndex npx hardhat run --network goerli scripts/deploy.js
$ CONTRACT_NAME=IndexManager npx hardhat run --network goerli scripts/deploy.js
$ # For IndexManager: add indexes
$ CONTRACT_NAME=IndexUtils npx hardhat run --network goerli scripts/deploy.js
```

## Verify

```sh
$ npx hardhat verify CONTRACT_ADDRESS --network goerli
$ # or
$ npx hardhat verify --constructor-args arguments.js CONTRACT_ADDRESS
```

## Flatten

You generally should not need to do this simply to verify in today's compiler version (0.8.x), but should you ever want to:

```sh
$ npx hardhat flatten {contract file location} > output.sol
```

const assert = require('assert')
const axios = require('axios')
const BigNumber = require('bignumber.js')
const {
  concat,
  createWalletClient,
  http,
  numberToHex,
  size,
  publicActions,
} = require('viem')
const { privateKeyToAccount } = require('viem/accounts')
const { createSafeClient } = require('@safe-global/sdk-starter-kit')
const { Counter } = require('./_utils')

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const deployerAddy = await deployer.getAddress()

  const nonce = await deployer.getTransactionCount()
  const nonceCounter = Counter(nonce - 1)

  const { chainId } = await ethers.provider.getNetwork()
  const peas = '0x02f92800f57bcd74066f5709f1daa1a4302df875'
  const permit2 = '0x000000000022d473030f116ddee9f6b43ac78ba3'

  const zeroxApiKey = process.env.ZEROX_API_KEY
  const safeAddy = process.env.SAFE
  const indexManager = process.env.INDEX_MANAGER
  const txMax = process.env.MAX || 10

  assert(zeroxApiKey, 'need ZEROX_API_KEY')
  assert(safeAddy, 'SAFE present')
  assert(indexManager, 'INDEX_MANAGER present')

  const starterClient = await createSafeClient({
    apiKey: process.env.SAFE_API_KEY,
    provider: hre.network.config.url,
    signer: process.env.PRIVATE_KEY,
    safeAddress: safeAddy,
  })

  const idxManager = await ethers.getContractAt('IndexManager', indexManager)
  const pods = await idxManager.allIndexes()

  let assetsProcessed = {} // address => bool
  let quoteResponses = {} // address => quoteResponse
  let transactions = []
  for (let _i = 0; _i < pods.length; _i++) {
    const podAddr = pods[_i].index

    const pod = await ethers.getContractAt('WeightedIndex', podAddr)
    const assetInfo = await pod.getAllAssets()
    const assetAddr = assetInfo[0].token

    // already processed this asset
    if (assetsProcessed[assetAddr.toLowerCase()]) {
      continue
    }

    assetsProcessed[assetAddr.toLowerCase()] = true

    // not selling PEAS
    if (new BigNumber(assetAddr.toLowerCase()).eq(peas.toLowerCase())) {
      continue
    }

    const asset = await ethers.getContractAt(
      '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol:IERC20Metadata',
      assetAddr
    )
    const safeAssetBal = await asset.balanceOf(safeAddy)
    const assetDecimals = await asset.decimals()
    if (
      new BigNumber(safeAssetBal.toString()).lte(
        new BigNumber('0.0001').times(
          new BigNumber(10).pow(assetDecimals.toString())
        )
      )
    ) {
      continue
    }

    const quoteRes = await getSwapQuote(
      zeroxApiKey,
      assetAddr,
      peas,
      safeAssetBal.toString(),
      safeAddy,
      chainId
    )

    if (!quoteRes.liquidityAvailable) {
      continue
    }
    // only sell token if we can buy >= 1 PEAS with this asset
    if (
      new BigNumber(quoteRes.buyAmount).lt(
        new BigNumber(1).times(new BigNumber(18))
      )
    ) {
      continue
    }

    quoteResponses[assetAddr.toLowerCase()] = quoteRes

    const transferData = asset.interface.encodeFunctionData('transfer', [
      deployerAddy,
      safeAssetBal.toString(),
    ])
    transactions.push({
      to: assetAddr,
      data: transferData,
      value: '0',
    })
    if (transactions.length >= txMax) {
      break
    }
  }

  if (transactions.length == 0) {
    console.log('No underlying to sell...')
    return
  }
  // console.log('TRANSACTIONS', transactions)
  const txResult = await starterClient.send({ transactions })
  nonceCounter.increment() // increment here after send
  console.log('safe transfer transaction to self', txResult)

  for (let _j = 0; _j < transactions.length; _j++) {
    const asset = transactions[_j].to

    const quoteRes = quoteResponses[asset.toLowerCase()]

    // check allowance to permit2 and approve if need be
    const assetCaObj = await ethers.getContractAt(
      '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol:IERC20Metadata',
      asset
    )
    const permitAllowance = await assetCaObj.allowance(deployerAddy, permit2)
    if (
      new BigNumber(permitAllowance.toString()).lt(
        quoteRes.sellAmount.toString()
      )
    ) {
      console.log('approving permit2 now', asset)
      const appRes = await assetCaObj.approve(
        permit2,
        new BigNumber(2).pow(256).minus(1).toFixed(),
        { nonce: nonceCounter.increment() }
      )
      console.log('permit2 approved', asset, appRes.hash)
    }

    console.log('sleeping 3 seconds...')
    await sleep(3000)

    const client = createWalletClient({
      account: privateKeyToAccount(
        process.env.PRIVATE_KEY.toString().slice(0, 2) == '0x'
          ? process.env.PRIVATE_KEY
          : `0x${process.env.PRIVATE_KEY}`
      ),
      chain: { id: chainId },
      transport: http(hre.network.config.url),
    }).extend(publicActions)
    const txData = await signTxData(client, quoteRes)

    const signedTx = await client.signTransaction({
      account: client.account,
      chain: client.chain,
      gas: !!quoteRes?.transaction.gas
        ? BigInt(quoteRes?.transaction.gas)
        : undefined,
      to: quoteRes?.transaction.to,
      data: txData,
      value: quoteRes?.transaction.value
        ? BigInt(quoteRes?.transaction.value)
        : undefined, // value is used for native tokens
      gasPrice: !!quoteRes?.transaction.gasPrice
        ? BigInt(quoteRes?.transaction.gasPrice)
        : undefined,
      nonce: nonceCounter.increment(),
    })
    const transactionRes = await client.sendRawTransaction({
      serializedTransaction: signedTx,
    })

    console.log('Sell tx hash:', transactionRes)
  }
}

async function getSwapQuote(
  apiKey,
  assetIn,
  assetOut,
  amountIn,
  recipient,
  chainId
) {
  const { data } = await axios.get(`https://api.0x.org/swap/permit2/quote`, {
    headers: {
      '0x-api-key': apiKey,
      '0x-version': 'v2',
    },
    params: {
      sellToken: assetIn,
      buyToken: assetOut,
      sellAmount: amountIn,
      slippageBps: 800, // 8% (https://0x.org/docs/0x-swap-api/guides/troubleshooting-swap-api)
      taker: recipient,
      chainId,
    },
  })
  return data
}

async function signTxData(client, quoteRes) {
  const signature = await client.signTypedData(quoteRes.permit2.eip712)
  const signatureLengthInHex = numberToHex(size(signature), {
    signed: false,
    size: 32,
  })
  return concat([quoteRes.transaction.data, signatureLengthInHex, signature])
}

async function sleep(milliseconds) {
  return await new Promise((resolve) => setTimeout(resolve, milliseconds))
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

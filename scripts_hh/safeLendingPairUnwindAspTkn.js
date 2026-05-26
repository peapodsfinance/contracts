const assert = require('assert')
const BigNumber = require('bignumber.js')
const { createSafeClient } = require('@safe-global/sdk-starter-kit')

async function main() {
  const [deployer] = await ethers.getSigners()
  const { chainId } = await ethers.provider.getNetwork()

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const unwindAspCas = {
    1: '0x88C6eECEB352d7e38cA8cd48f3d2642c91dF3DB3', // mainnet
    42161: '0xE7CAed3c6Ea6F1db7a0bF02ff45cdB8B86DFc805', // arbitrum
    8453: '0x7b0079453d9C54F573c23338b2f850b694125714', // base
    146: '0xF79E973cA79e06B77E48A1DF37109F80Dcc598bb', // sonic
  }
  const unwindAspAddr = unwindAspCas[chainId]
  const unwindAsp = await ethers.getContractAt('UnwindAspTkn', unwindAspAddr)

  const safeAddy = process.env.SAFE
  const indexManager = process.env.INDEX_MANAGER
  const levMgr = process.env.LVF
  const txMax = process.env.MAX || 0

  assert(safeAddy, 'SAFE present')
  assert(indexManager, 'INDEX_MANAGER present')
  assert(levMgr, 'LVF present')

  const safeClient = await createSafeClient({
    apiKey: process.env.SAFE_API_KEY,
    provider: hre.network.config.url,
    signer: process.env.PRIVATE_KEY,
    safeAddress: safeAddy,
  })

  const levManager = await ethers.getContractAt('LeverageManager', levMgr)
  const idxManager = await ethers.getContractAt('IndexManager', indexManager)
  const pods = await idxManager.allIndexes()

  let transactions = []
  for (let _i = 0; _i < pods.length; _i++) {
    const podAddr = pods[_i].index
    const lendingPairAddr = await levManager.lendingPairs(podAddr)
    if (BigNumber(lendingPairAddr.toLowerCase()).lte(0)) {
      continue
    }
    const pair = await ethers.getContractAt('IFraxlendPair', lendingPairAddr)
    const aspTknAddr = await pair.collateralContract()
    const aspTkn = await ethers.getContractAt('IERC20', aspTknAddr)
    const aspTknBal = await aspTkn.balanceOf(safeAddy)
    if (new BigNumber(aspTknBal.toString()).lte('1000000')) {
      continue
    }

    const approvedAmt = await aspTkn.allowance(safeAddy, unwindAspAddr)
    if (new BigNumber(approvedAmt.toString()).lte(0)) {
      const approveData = aspTkn.interface.encodeFunctionData('approve', [
        unwindAspAddr,
        new BigNumber(2).pow(256).minus(1).toFixed(0),
      ])
      transactions.push({ to: aspTknAddr, data: approveData, value: '0' })
    }

    const unwindData = unwindAsp.interface.encodeFunctionData('unwindAspTkn', [
      aspTknAddr,
      aspTknBal,
    ])
    transactions.push({ to: unwindAspAddr, data: unwindData, value: '0' })
    console.log(
      'Unwinding from',
      podAddr,
      lendingPairAddr,
      aspTknAddr,
      aspTknBal.toString()
    )

    if (txMax && txMax > 0 && transactions.length / 2 >= txMax) {
      break
    }
  }

  if (transactions.length > 0) {
    const txResult = await safeClient.send({ transactions })
    console.log(
      'Sent transaction',
      txResult?.transactions?.ethereumTxHash,
      txResult?.transactions?.safeTxHash
    )
  } else {
    console.log('no aspTKN to unwind...')
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

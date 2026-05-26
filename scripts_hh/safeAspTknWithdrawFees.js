const assert = require('assert')
const BigNumber = require('bignumber.js')
const { createSafeClient } = require('@safe-global/sdk-starter-kit')

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const safeAddy = process.env.SAFE
  const withdrawerAddy = process.env.WITHDRAWER
  const indexManager = process.env.INDEX_MANAGER
  const levMgr = process.env.LVF
  const txMax = process.env.MAX || 100

  assert(safeAddy, 'SAFE present')
  assert(withdrawerAddy, 'withdrawerAddy present')
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
    const pairAddr = await levManager.lendingPairs(podAddr)
    if (BigNumber(pairAddr.toLowerCase()).gt(0)) {
      const pod = await ethers.getContractAt('WeightedIndex', podAddr)
      const lendingPair = await ethers.getContractAt('IFraxlendPair', pairAddr)
      const aspTknAddr = await lendingPair.collateralContract()
      // const pairedLpTkn = await ethers.getContractAt(
      //   'IERC20',
      //   await pod.PAIRED_LP_TOKEN()
      // )
      // const hasPendingFees =
      //   BigInt(await pod.balanceOf(podAddr)) > 0n &&
      //   BigInt(await lendingPair.totalSupply()) > 0n &&
      //   BigInt(await pairedLpTkn.balanceOf(aspTknAddr)) > 0n
      // if (hasPendingFees) {
      const withdrawer = await ethers.getContractAt(
        'AutoCompoundingPodLpSilentFeeWithdrawer',
        withdrawerAddy
      )
      const withdrawFeesData = withdrawer.interface.encodeFunctionData(
        'withdrawProtocolFees',
        [aspTknAddr]
      )
      transactions.push({
        to: withdrawerAddy,
        data: withdrawFeesData,
        value: '0',
      })
      console.log('Withdrawing fees', aspTknAddr)
      // }
    }

    if (transactions.length >= txMax) {
      break
    }
  }

  const txResult = await safeClient.send({ transactions })
  console.log('Sent transaction', txResult?.transactions?.ethereumTxHash)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

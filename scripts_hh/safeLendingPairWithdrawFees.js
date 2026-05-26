const assert = require('assert')
const BigNumber = require('bignumber.js')
const { createSafeClient } = require('@safe-global/sdk-starter-kit')

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Account balance:', (await deployer.getBalance()).toString())

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
    if (BigNumber(lendingPairAddr.toLowerCase()).gt(0)) {
      const lendingPair = await ethers.getContractAt(
        'IFraxlendPair',
        lendingPairAddr
      )

      const owner = await lendingPair.owner()
      // can't withdraw fees if our safe not the owner
      if (
        !new BigNumber(owner.toLowerCase()).isEqualTo(safeAddy.toLowerCase())
      ) {
        continue
      }

      // const shares = await lendingPair.maxRedeem(lendingPairAddr)
      const shares = await lendingPair.balanceOf(lendingPairAddr)
      if (new BigNumber(shares.toString()).lte('1000000')) {
        continue
      }

      const assetAddr = await lendingPair.asset()
      const asset = await ethers.getContractAt('IERC20', assetAddr)
      const assetsFromShares = await lendingPair.convertToAssets(shares)
      const assetsInPair = await asset.balanceOf(lendingPairAddr)
      if (
        new BigNumber(assetsInPair.toString()).lt(assetsFromShares.toString())
      ) {
        continue
      }

      const withdrawFeesData = lendingPair.interface.encodeFunctionData(
        'withdrawFees',
        [shares, safeAddy]
      )
      transactions.push({
        to: lendingPairAddr,
        data: withdrawFeesData,
        value: '0',
      })
      console.log(
        'Withdrawing fees from',
        lendingPairAddr,
        shares.toString(),
        withdrawFeesData
      )
    }
    if (txMax && txMax > 0 && transactions.length >= txMax) {
      break
    }
  }

  const txResult = await safeClient.send({ transactions })
  console.log('Sent transaction', txResult)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

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
        '@openzeppelin/contracts/interfaces/IERC4626.sol:IERC4626',
        lendingPairAddr
      )
      const assetAddr = await lendingPair.asset()
      const asset = await ethers.getContractAt('IERC20', assetAddr)
      // const pairRedeemable = await lendingPair.maxRedeem(safeAddy)
      const safeShares = await lendingPair.balanceOf(safeAddy)
      const totalSharesInPair = await lendingPair.convertToShares(
        await asset.balanceOf(lendingPairAddr)
      )
      const pairRedeemable = new BigNumber(safeShares.toString()).gt(
        totalSharesInPair.toString()
      )
        ? totalSharesInPair
        : safeShares
      if (new BigNumber(pairRedeemable.toString()).gt('1000000')) {
        const redeemData = lendingPair.interface.encodeFunctionData('redeem', [
          new BigNumber(pairRedeemable.toString()).minus('10').toFixed(0),
          safeAddy,
          safeAddy,
        ])
        transactions.push({ to: lendingPairAddr, data: redeemData, value: '0' })
        console.log(
          'Redeeming from',
          lendingPairAddr,
          assetAddr,
          new BigNumber(pairRedeemable.toString())
            .div(new BigNumber(10).pow(await lendingPair.decimals()))
            .toFixed(9),
          redeemData
        )
      }
    }
    if (txMax && txMax > 0 && transactions.length >= txMax) {
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

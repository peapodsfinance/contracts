const assert = require('assert')
const BigNumber = require('bignumber.js')
const { createSafeClient } = require('@safe-global/sdk-starter-kit')

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const peas = '0x02f92800f57bcd74066f5709f1daa1a4302df875'

  const safeAddy = process.env.SAFE
  const indexManager = process.env.INDEX_MANAGER
  const levMgr = process.env.LVF
  const txMax = process.env.MAX || 100

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

    // // NOTE: for now only debond from LVF pods
    // const lendingPairAddr = await levManager.lendingPairs(podAddr)
    // if (BigNumber(lendingPairAddr.toLowerCase()).eq(0)) {
    //   continue
    // }

    const pod = await ethers.getContractAt('WeightedIndex', podAddr)
    const assetInfo = await pod.getAllAssets()
    const pairedLpTknAddy = await pod.PAIRED_LP_TOKEN()
    const pairedLpTkn = await ethers.getContractAt('IERC20', pairedLpTknAddy)
    const spTknAddy = await pod.lpStakingPool()
    const spTkn = await ethers.getContractAt('StakingPoolToken', spTknAddy)
    const uniV2PairAddy = await spTkn.stakingToken()
    // const uniV2Pair = await ethers.getContractAt('IERC20', uniV2PairAddy)
    const pTknLpBal = await pod.balanceOf(uniV2PairAddy)
    const pairedLpBal = await pairedLpTkn.balanceOf(uniV2PairAddy)
    if (
      (new BigNumber(pTknLpBal.toString()).gt('0') &&
        new BigNumber(pTknLpBal.toString()).lt('100')) ||
      (new BigNumber(pairedLpBal.toString()).gt('0') &&
        new BigNumber(pairedLpBal.toString()).lt('100'))
    ) {
      continue
    }

    const tkn = await ethers.getContractAt(
      '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol:IERC20Metadata',
      assetInfo[0].token
    )
    const safePodBal = await pod.balanceOf(safeAddy)
    if (
      new BigNumber(safePodBal.toString()).lte(
        new BigNumber('0.1').times(new BigNumber(10).pow(18))
      )
    ) {
      continue
    }

    const debondData = pod.interface.encodeFunctionData('debond', [
      safePodBal.toString(),
      [],
      [],
    ])

    transactions.push({
      to: podAddr,
      data: debondData,
      value: '0',
    })
    console.log(
      'Debonding from',
      podAddr,
      new BigNumber(safePodBal.toString())
        .div(new BigNumber(10).pow(18))
        .toFixed(),
      await pod.symbol(),
      `(${await tkn.symbol()})`
    )

    if (transactions.length >= txMax) {
      break
    }
  }

  if (transactions.length > 0) {
    const txResult = await safeClient.send({ transactions })
    console.log('Sent transaction', txResult)
  } else {
    console.log('Not debonding from any pods...')
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

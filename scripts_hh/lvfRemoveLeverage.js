const assert = require('assert')
const BigNumber = require('bignumber.js')
const { Counter } = require('./_utils')

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Deploying contracts with the account:', deployer.address)

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const lvfCa = process.env.LVF
  const posId = process.env.POS_ID
  assert(lvfCa && posId, 'LVF present')

  const nonce = await deployer.getTransactionCount()
  const nonceCounter = Counter(nonce - 1)

  const leverageManager = await ethers.getContractAt('LeverageManager', lvfCa)
  await leverageManager.removeLeverage(
    posId,
    '1000', // _borrowAssetAmt
    '15811388', // _collateralAssetRemoveAmt
    '0',
    '0',
    '0x83EcCba9F04c94A6C520114c48F493095E823F94', // dexAdapter
    '1000000000000000000000', // _userProvidedDebtAmtMax
    {
      nonce: nonceCounter.increment(),
      // gasLimit: '10000000',
    }
  )
  console.log('Remove leverage complete')
  console.log('Script complete!')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

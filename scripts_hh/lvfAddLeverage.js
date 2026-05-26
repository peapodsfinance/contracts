const assert = require('assert')
const BigNumber = require('bignumber.js')
const { Counter } = require('./_utils')

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Deploying contracts with the account:', deployer.address)

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const lvfCa = process.env.LVF
  assert(lvfCa, 'LVF present')

  const nonce = await deployer.getTransactionCount()
  const nonceCounter = Counter(nonce - 1)

  const leverageManager = await ethers.getContractAt('LeverageManager', lvfCa)
  await leverageManager.addLeverage(
    0,
    // '0xc604c6c646bb7a49d5829fbc479bb7b1b4da17f3', // apPEASUSDC
    '0x390b35eb4D51B5CD1AA67ccA52A7824d7e203537', // self lending test
    '10000000000000',
    '1000',
    '0',
    '1000',
    Math.floor(Date.now() / 1000) + 60,
    '0x0000000000000000000000000000000000000000',
    {
      nonce: nonceCounter.increment(),
      // gasLimit: '10000000',
    }
  )
  console.log('Add leverage complete')
  console.log('Script complete!')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

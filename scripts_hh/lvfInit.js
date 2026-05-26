const assert = require('assert')
const BigNumber = require('bignumber.js')
const { Counter } = require('./_utils')

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Deploying contracts with the account:', deployer.address)

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const lvfCa = process.env.LVF
  const pod = process.env.POD
  // const pod = '0xc604c6c646bb7a49d5829fbc479bb7b1b4da17f3' // apPEASUSDCCa
  assert(lvfCa, 'LVF present')

  const nonce = await deployer.getTransactionCount()
  const nonceCounter = Counter(nonce - 1)

  const usdcCa = '0xaf88d065e77c8cC2239327C5EDb3A432268e5831'
  const usdc = await ethers.getContractAt('IERC20', usdcCa)
  await usdc.approve(lvfCa, new BigNumber(2).pow(96).minus(1).toFixed(0), {
    nonce: nonceCounter.increment(),
  })
  const apPEAS = await ethers.getContractAt('IERC20', pod)
  await apPEAS.approve(lvfCa, new BigNumber(2).pow(96).minus(1).toFixed(0), {
    nonce: nonceCounter.increment(),
  })
  console.log('Approval complete')

  const leverageManager = await ethers.getContractAt('LeverageManager', lvfCa)
  await leverageManager.setLendingPair(
    pod,
    '0x168f49F01DabDAC4161393960BE4F612F698faa4',
    {
      nonce: nonceCounter.increment(),
    }
  )
  console.log('Set pair complete')

  await leverageManager.setFlashSource(
    pod,
    '0x6F8141484Ee7066d1B952081086f347639694B68',
    {
      nonce: nonceCounter.increment(),
    }
  )
  console.log('Set flash source complete')

  console.log('Script complete!')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

const assert = require('assert')

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Deploying contracts with the account:', deployer.address)

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const lvfCa = process.env.LVF
  const posId = process.env.POS_ID
  assert(lvfCa && posId, 'LVF & POS_ID present')

  const leverageManager = await ethers.getContractAt('LeverageManager', lvfCa)
  const props = await leverageManager.positionProps(posId)
  console.log(`${posId} Props:`, props)
  console.log('Script complete!')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

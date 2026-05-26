const assert = require('assert')

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Deploying contracts with the account:', deployer.address)

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const aspDepCa = process.env.ASPD
  assert(aspDepCa, 'ASPD present')

  const aspDeployer = await ethers.getContractAt(
    'AutoCompoundingPodLpFactory',
    aspDepCa
  )
  await aspDeployer.setMinimumDepositAtCreation('0')
  console.log(`Successfully set min deposit`)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

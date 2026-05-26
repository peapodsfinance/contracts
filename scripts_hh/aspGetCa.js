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
  // const ca = await aspDeployer.create(
  const ca = await aspDeployer.getNewCaFromParams(
    'zzzzAPP',
    'zAPP',
    // '0xc604c6c646bb7a49d5829fbc479bb7b1b4da17f3', // pod (apPEASUSDC)
    '0x0000000000000000000000000000000000000000', // empty pod to set later
    '0x83EcCba9F04c94A6C520114c48F493095E823F94', // dexAdapter
    '0x5c5c288f5EF3559Aaf961c5cCA0e77Ac3565f0C0', // indexUtils
    '0x925C14e51Cc45BC64F66cc782503Fb0C4bC3FCF0', // rewardsWhitelist
    '0x88B6dB67000F8Ef34AE1a34542B2E4b43B87d9b7', // v3TwapUtils
    '0' // salt
    // { gasLimit: '10000000' }
  )
  console.log(`new AutoCompoundingPodLp CA: ${ca}`)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

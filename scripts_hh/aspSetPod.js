const assert = require('assert')

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Deploying contracts with the account:', deployer.address)

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const aspTknCa = process.env.ASP
  const pod = process.env.POD
  assert(aspTknCa && pod, 'ASP & POD present')

  const aspTkn = await ethers.getContractAt('AutoCompoundingPodLp', aspTknCa)
  await aspTkn.setPod(pod)
  console.log(`Successfully set pod`)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

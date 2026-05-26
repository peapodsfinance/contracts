const assert = require('assert')
const { Counter } = require('./_utils')

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Deploying contracts with the account:', deployer.address)

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const nonce = await deployer.getTransactionCount()
  const nonceCounter = Counter(nonce - 1)

  const vaultCa = process.env.VAULT
  const wl = process.env.WL
  assert(vaultCa && wl, 'VAULT & WL present')

  const vault = await ethers.getContractAt('LendingAssetVault', vaultCa)
  await vault.setVaultWhitelist(wl, true, {
    nonce: nonceCounter.increment(),
  })
  console.log('Set vault wl!')

  await vault.setVaultMaxAllocation(wl, '10000', {
    nonce: nonceCounter.increment(),
  })
  console.log('Set vault wl max!')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

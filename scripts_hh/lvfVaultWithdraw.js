const assert = require('assert')
const BigNumber = require('bignumber.js')
const { Counter } = require('./_utils')

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Deploying contracts with the account:', deployer.address)

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const nonce = await deployer.getTransactionCount()
  const nonceCounter = Counter(nonce - 1)

  const vaultCa = process.env.VAULT
  assert(vaultCa, 'VAULT present')

  const usdcCa = '0xaf88d065e77c8cC2239327C5EDb3A432268e5831'
  const usdc = await ethers.getContractAt(
    '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol:IERC20Metadata',
    usdcCa
  )

  const vault = await ethers.getContractAt('LendingAssetVault', vaultCa)
  await vault.withdraw(
    new BigNumber('0.01')
      .times(new BigNumber(10).pow(await usdc.decimals()))
      .toFixed(0),
    deployer.address,
    deployer.address,
    {
      nonce: nonceCounter.increment(),
    }
  )
  console.log('Script complete!')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

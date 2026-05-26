const assert = require('assert')
const BigNumber = require('bignumber.js')
const { Counter } = require('./_utils')

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Deploying contracts with the account:', deployer.address)

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const nonce = await deployer.getTransactionCount()
  const nonceCounter = Counter(nonce - 1)

  const usdcCa = '0xaf88d065e77c8cC2239327C5EDb3A432268e5831'

  const Contract = await ethers.getContractFactory('LendingAssetVault')
  const contract = await Contract.deploy('zzzLAV', 'zLAV', usdcCa, {
    nonce: nonceCounter.increment(),
  })

  console.log('Contract address:', contract.address)

  const usdc = await ethers.getContractAt(
    '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol:IERC20Metadata',
    usdcCa
  )
  await usdc.approve(
    contract.address,
    new BigNumber(2).pow(96).minus(1).toFixed(0),
    {
      nonce: nonceCounter.increment(),
    }
  )
  console.log('USDC approved!')
  console.log('Script complete!')
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

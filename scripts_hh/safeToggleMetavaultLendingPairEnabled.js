const assert = require('assert')
const BigNumber = require('bignumber.js')
const { createSafeClient } = require('@safe-global/sdk-starter-kit')

async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const safeAddy = process.env.SAFE
  const metavaultAddr = process.env.MV
  const lendingPairAddr = process.env.PAIR
  const isEnabled = process.env.ENABLED !== 'false'
  const desiredMaxAlloProvided = process.env.ALLO

  assert(safeAddy, 'SAFE present')
  assert(metavaultAddr, 'MV present')
  assert(lendingPairAddr, 'PAIR present')

  const safeClient = await createSafeClient({
    apiKey: process.env.SAFE_API_KEY,
    provider: hre.network.config.url,
    signer: process.env.PRIVATE_KEY,
    safeAddress: safeAddy,
  })

  const lendingPair = await ethers.getContractAt(
    'IFraxlendPair',
    lendingPairAddr
  )
  const metavault = await ethers.getContractAt(
    'LendingAssetVault',
    metavaultAddr
  )

  console.log('owner pair', await lendingPair.owner())
  console.log('owner MV', await metavault.owner())

  const setVaultData = lendingPair.interface.encodeFunctionData(
    'setExternalAssetVault',
    [isEnabled ? metavaultAddr : '0x0000000000000000000000000000000000000000']
  )
  const setMvPair = metavault.interface.encodeFunctionData(
    'setVaultWhitelist',
    [lendingPairAddr, isEnabled]
  )

  const doesMvHavePairSet = await metavault.vaultWhitelist(lendingPairAddr)
  // const doesPairHaveMvSet = BigInt(await lendingPair.externalAssetVault()) > 0n
  const pairOwner = await lendingPair.owner()

  let transactions = []
  const shouldAddToggleTx =
    (!doesMvHavePairSet && isEnabled) || (doesMvHavePairSet && !isEnabled)
  if (shouldAddToggleTx) {
    transactions.push({
      to: metavaultAddr,
      data: setMvPair,
      value: '0',
    })
    console.log(`added tx to toggle pair in MV`)
  }

  if (BigInt(pairOwner.toString()) != BigInt(safeAddy)) {
    console.log('not adjusting pair since owner is now SAFE')
  } else if (shouldAddToggleTx) {
    transactions.push({
      to: lendingPairAddr,
      data: setVaultData,
      value: '0',
    })
    console.log(`added tx to toggle MV in pair`)
  }

  if (isEnabled && typeof desiredMaxAlloProvided !== 'undefined') {
    const currentPairMaxAllo = await metavault.vaultMaxAllocation(
      lendingPairAddr
    )
    // only change max allo if it's different than current
    let desiredMaxAlloRaw = desiredMaxAlloProvided
    if (new BigNumber(desiredMaxAlloRaw).isNaN()) {
      desiredMaxAlloRaw = currentPairMaxAllo.toString()
    } else if (
      !new BigNumber(currentPairMaxAllo.toString()).isEqualTo(desiredMaxAlloRaw)
    ) {
      const setPairAlloInMvData = metavault.interface.encodeFunctionData(
        'setVaultMaxAllocation',
        [[lendingPairAddr], [desiredMaxAlloRaw]]
      )
      transactions.push({
        to: metavaultAddr,
        data: setPairAlloInMvData,
        value: '0',
      })
      console.log(`added tx to set pair max allocation: ${desiredMaxAlloRaw}`)
    }

    // check allo and deposit into pair if needed
    // const availableToDeposit = await metavault.totalAvailableAssetsForVault(
    //   lendingPairAddr
    // )
    const availableToDeposit = await metavault.totalAvailableAssets()
    const currentPairAllo = await metavault.vaultUtilization(lendingPairAddr)
    if (new BigNumber(desiredMaxAlloRaw).gt(currentPairAllo.toString())) {
      // TODO: find out what the appropriate amount to deposit to get to MV utilization == 80% and adjust as needed

      const amtToDeposit = new BigNumber(desiredMaxAlloRaw).gt(
        availableToDeposit.toString()
      )
        ? availableToDeposit.toString()
        : desiredMaxAlloRaw
      const depositAmtRaw = new BigNumber(amtToDeposit)
        .minus(currentPairAllo.toString())
        .toFixed(0)
      const depositToVaultData = metavault.interface.encodeFunctionData(
        'depositToVault',
        [lendingPairAddr, depositAmtRaw]
      )
      transactions.push({
        to: metavaultAddr,
        data: depositToVaultData,
        value: '0',
      })
      console.log(`added tx to deposit to vault from MV: ${depositAmtRaw}`)
    }
  }

  if (transactions.length > 0) {
    const txResult = await safeClient.send({ transactions })
    console.log('Sent transaction', txResult)
  } else {
    console.log('DID NOT send any transactions')
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

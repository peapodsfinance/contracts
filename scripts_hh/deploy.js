async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Deploying contracts with the account:', deployer.address)

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const Contract = await ethers.getContractFactory(process.env.CONTRACT_NAME)
  // contract constructor arguments can be passed as parameters in #deploy
  // await Contract.deploy(arg1, arg2, ...)
  // TODO: make configurable through CLI params
  const contract = await Contract.deploy(
    // // TestERC20: ETH Sepolia, Arb Sepolia, & Op Sepolia
    // 'bTEST',
    // 'bTEST'
    // // TokenBridge: ETH Sepolia
    // '0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59',
    // '0x3B57D742f3D023FA97C622584db9C235650c1653'
    // // TokenBridge: Optimism Sepolia
    // '0x114a20a10b43d4115e5aeef7345a1a71d2a60c57',
    // '0x0BdA2fa3C83b0EF7f67EB28A056798451c0B90f5'
    // // TokenBridge: Arbitrum Sepolia
    // '0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165',
    // '0x0cB1E2f826ECBfEF9456Fd423b69325e986956f7'

    // Weighted: ETH Sepolia
    'Verification',
    'pVER',
    ['0x0000000000000000000000000000000000000000', '604800', false, false],
    [2000, 100, 100, 50, 50, 0],
    ['0x02f92800F57BCD74066F5709F1Daa1A4302Df875'],
    [100],
    false,
    false,
    ethers.utils.defaultAbiCoder.encode(
      [
        'address',
        'address',
        'address',
        'address',
        'address',
        'address',
        'address',
      ],
      [
        '0x68194a729C2450ad26072b3D33ADaCbcef39D574',
        '0x02f92800F57BCD74066F5709F1Daa1A4302Df875',
        '0x68194a729C2450ad26072b3D33ADaCbcef39D574',
        '0xFb651B21f14D24018a06998402C5Ef9927Aaab69',
        '0x09D0FFa7EB3bBEc52E05310E696C7C6BB4f973b4',
        '0xC67009293ec940B685A1B2f640DDBefc8C332A67',
        '0x5c57558c39151DCc0831eb36A52769Bf6887EA2F',
      ]
    )

    // // IndexUtils: ETH Mainnet
    // '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D',
    // '0x024ff47D552cB222b265D68C7aeB26E586D5229D'

    // // ArbitragePP
    // '0x024ff47D552cB222b265D68C7aeB26E586D5229D',
    // '0x1F98431c8aD98523631AE4a59f267346ea31F984',
    // '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'

    // ******************************************
    // ******************************************
    // // wduiTEST: Arbitrum One Mainnet
    // ['0xB5426d6d4724544ebfBa39630d5360B7feA87262'],
    // ['1000000'],
    // '0xB5426d6d4724544ebfBa39630d5360B7feA87262',
    // '0xc873fEcbd354f5A56E00E710B90EF4201db2448d',
    // ['0x0000000000000000000000000000000000000000', false, false],
    // [2000, 100, 100, 100, 100, 0]

    // // IndexUtils: Arbitrum One Mainnet
    // '0x88B6dB67000F8Ef34AE1a34542B2E4b43B87d9b7',
    // '0x83EcCba9F04c94A6C520114c48F493095E823F94'
    // // ERC20Bridgeable
    // 'Peapods',
    // 'PEAS'

    // // UniswapDexAdapter: Ethereum Mainnet
    // '0x024ff47D552cB222b265D68C7aeB26E586D5229D',
    // '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D',
    // '0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45',
    // false

    // // (TEST) UniswapDexAdapter (Uni/Sushiswap): Arbitrum One
    // '0x024ff47D552cB222b265D68C7aeB26E586D5229D',
    // '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506',
    // '0xE592427A0AEce92De3Edee1F18E0157C05861564',
    // false
    // // CamelotDexAdapter (Camelot): Arbitrum One
    // '0x88B6dB67000F8Ef34AE1a34542B2E4b43B87d9b7',
    // '0xc873fEcbd354f5A56E00E710B90EF4201db2448d',
    // '0x1F721E2E82F6676FCE4eA07A5958cF098D339e18'
    // // AerodromeDexAdapter (Aerodrome): Base
    // '0x024ff47D552cB222b265D68C7aeB26E586D5229D',
    // '0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43',
    // '0x6Cb442acF35158D5eDa88fe602221b67B400Be3E'

    // // spTKNOracle - Arbitrum apPEASUSDC
    // '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
    // '0x21a4F940E58271a733ecF2A262fDf62cd10a1132',
    // '0xCF71459248557807b87CF988F30aE7845F7bD6D5',
    // '0x88B6dB67000F8Ef34AE1a34542B2E4b43B87d9b7'

    // // PodFlashSource - Arbitrum apPEAS
    // '0x6a02f704890f507f13d002f2785ca7ba5bfcc8f7',
    // '0xda10009cbd5d07dd0cecc66161fc93d7c9000da1'

    // // LeverageManager - Arbitrum testing
    // 'zzzLTest',
    // 'zZLT',
    // '0x5c5c288f5EF3559Aaf961c5cCA0e77Ac3565f0C0'
  )

  console.log('Contract address:', contract.address)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

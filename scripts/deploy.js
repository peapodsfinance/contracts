async function main() {
  const [deployer] = await ethers.getSigners()

  console.log('Deploying contracts with the account:', deployer.address)

  console.log('Account balance:', (await deployer.getBalance()).toString())

  const Contract = await ethers.getContractFactory(process.env.CONTRACT_NAME)
  // contract constructor arguments can be passed as parameters in #deploy
  // await Contract.deploy(arg1, arg2, ...)
  // TODO: make configurable through CLI params
  const contract = await Contract.deploy(
    // // UnweightedIndex: ETH Mainnet
    // 'Peapods Blue Chips (Unweighted)',
    // 'ppBLUE',
    // 100,
    // 300,
    // [
    //   '0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0', // WBTC/WETH
    //   '0xa6Cc3C2531FdaA6Ae1A3CA84c2855806728693e8', // LINK/WETH
    //   '0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640', // WETH/USDC
    // ],
    // '0x02f92800F57BCD74066F5709F1Daa1A4302Df875',
    // '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D',
    // '0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640',
    // '0x6B175474E89094C44Da98b954EedeAC495271d0F',
    // false,
    // '0x024ff47D552cB222b265D68C7aeB26E586D5229D'

    // // Weighted: ETH Mainnet
    // 'PEA,PEA (Weighted)',
    // 'ppPP',
    // 100,
    // 300,
    // [
    //   // '0x6982508145454ce325ddbe47a25d4ec3d2311933',
    //   // '0x72e4f9f808c49a2a61de9c5896298920dc4eeea9',
    //   // '0xcf0c122c6b73ff809c693db761e7baebe62b6a2e',
    //   // '0x95ad61b0a150d79219dcf64e1e6cc01f0b64c4ce',
    //   '0x02f92800f57bcd74066f5709f1daa1a4302df875',
    // ],
    // // [100000, 1, 2000, 5000],
    // [1],
    // '0x02f92800F57BCD74066F5709F1Daa1A4302Df875',
    // '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D',
    // '0x6B175474E89094C44Da98b954EedeAC495271d0F',
    // false,
    // '0x024ff47D552cB222b265D68C7aeB26E586D5229D'

    // // IndexUtils: ETH Mainnet
    // '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D',
    // '0x024ff47D552cB222b265D68C7aeB26E586D5229D'

    // // ArbitragePP
    // '0x024ff47D552cB222b265D68C7aeB26E586D5229D',
    // '0x1F98431c8aD98523631AE4a59f267346ea31F984',
    // '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'

    // ******************************************
    // ******************************************
    // // uwduiTEST: Arbitrum One Mainnet
    // [
    //   '0x2f5e87C9312fa29aed5c179E456625D79015299c', // WBTC/WETH
    //   '0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443', // WETH/USDC
    //   '0x468b88941e7Cc0B88c1869d68ab6b570bCEF62Ff', // LINK/WETH
    //   // '0x1aeedd3727a6431b8f070c0afaa81cc74f273882', // GMX/WETH
    //   // '0x446bf9748b4ea044dd759d9b9311c70491df8f29', // RDNT/WETH
    //   // '0xc91b7b39bbb2c733f0e7459348fd0c80259c8471', // GNS/WETH
    //   // '0x05bbaaa020ff6bea107a9a1e06d2feb7bfd79ed2', // HMX/WETH
    //   // '0xdbaeb7f0dfe3a0aafd798ccecb5b22e708f7852c', // PENDLE/WETH
    //   // '0xc6f780497a95e246eb9449f5e4770916dcd6396a', // ARB/WETH
    //   // '0x641c00a822e8b671738d32a431a4fb6074e5c79d', // USDT/WETH
    // ],
    // '0xB5426d6d4724544ebfBa39630d5360B7feA87262',
    // '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506',
    // '0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443',
    // '0xda10009cbd5d07dd0cecc66161fc93d7c9000da1',
    // '0xA409ae56bf422C7e58DA0265d6B2edA3fb846283'

    // // wduiTEST: Arbitrum One Mainnet
    // [
    //   '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f', // WBTC
    //   '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1', // WETH
    //   // '0xf97f4df75117a78c1a5a0dbb814af92458539fb4', // LINK
    //   '0xfc5a1a6eb076a2c7ad06ed22c90d7e710e35ad0a', // GMX
    //   // '0x3082cc23568ea640225c2467653db90e9250aaa0', // RDNT
    //   // '0x18c11FD286C5EC11c3b683Caa813B77f5163A122', // GNS
    // ],
    // [1, 10, 400],
    // '0xB5426d6d4724544ebfBa39630d5360B7feA87262',
    // '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506',
    // '0xda10009cbd5d07dd0cecc66161fc93d7c9000da1',
    // '0xA409ae56bf422C7e58DA0265d6B2edA3fb846283'

    // // wduiTEST: xTST Arbitrum One Mainnet
    // [
    //   '0xB5426d6d4724544ebfBa39630d5360B7feA87262', // xTST
    // ],
    // [1],
    // '0xB5426d6d4724544ebfBa39630d5360B7feA87262',
    // '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506',
    // [100, 100, 300, 0, 0, 0]

    // IndexUtils: Arbitrum One Mainnet
    '0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506',
    '0xA409ae56bf422C7e58DA0265d6B2edA3fb846283'
  )

  console.log('Contract address:', contract.address)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

require('@nomicfoundation/hardhat-foundry')

// import "@nomiclabs/hardhat-etherscan";
require('@nomiclabs/hardhat-etherscan')
// import "@nomiclabs/hardhat-waffle";
require('@nomiclabs/hardhat-waffle')
// import "hardhat-contract-sizer";
require('hardhat-contract-sizer')
// import "hardhat-gas-reporter";
require('hardhat-gas-reporter')
// import '@openzeppelin/hardhat-upgrades';
require('@openzeppelin/hardhat-upgrades')
// import "solidity-coverage";
require('solidity-coverage')

// import { resolve } from "path";
const { resolve } = require('path')

// import { config as dotenvConfig } from "dotenv";
const { config: conf } = require('dotenv')
const dotenvConfig = conf

dotenvConfig({ path: resolve(__dirname, './.env') })

const chainIds = {
  arbitrum: 42161,
  arbgoerli: 421613,
  arbsep: 421614,
  base: 8453,
  bsc: 56,
  kcc: 321,
  polygon: 137,
  ganache: 1337,
  goerli: 5,
  hardhat: 31337,
  mainnet: 1,
  mode: 34443,
  sepolia: 11155111,
  opsep: 11155420,
}

// Ensure that we have all the environment variables we need.
const privateKey = process.env.PRIVATE_KEY
if (!privateKey) {
  throw new Error('Please set your PRIVATE_KEY in a .env file')
}
// const mnemonic = process.env.MNEMONIC;
// if (!mnemonic) {
//   throw new Error("Please set your MNEMONIC in a .env file");
// }

// const infuraApiKey = process.env.INFURA_API_KEY
// if (!infuraApiKey) {
//   throw new Error('Please set your INFURA_API_KEY in a .env file')
// }

function createConfig(network, rpcUrl = null) {
  const url = rpcUrl || 'https://ethereum.publicnode.com' // `https://${network}.infura.io/v3/${infuraApiKey}`
  return {
    accounts: [privateKey],
    // accounts: {
    //   count: 10,
    //   initialIndex: 0,
    //   mnemonic,
    //   path: "m/44'/60'/0'/0",
    // },
    chainId: chainIds[network] || 1,
    url,
  }
}

const config = {
  defaultNetwork: 'hardhat',
  etherscan: {
    // apiKey: process.env.ARBISCAN_API_KEY,
    // apiKey: process.env.ETHERSCAN_API_KEY,
    // apiKey: process.env.BASESCAN_API_KEY,
    // apiKey: process.env.BSCSCAN_API_KEY,
    apiKey: process.env.MODE_API_KEY,
    // apiKey: process.env.POLYGONSCAN_API_KEY,

    customChains: [
      {
        network: 'base',
        chainId: 8453,
        urls: {
          apiURL: 'https://api.basescan.org/api',
          browserURL: 'https://basescan.org',
        },
      },
      {
        network: 'mode',
        chainId: 34443,
        urls: {
          apiURL: 'https://explorer.mode.network/api',
          browserURL: 'https://explorer.mode.network',
        },
      },
    ],
  },
  gasReporter: {
    currency: 'USD',
    enabled: process.env.REPORT_GAS ? true : false,
    excludeContracts: [],
    src: './contracts',
  },
  networks: {
    hardhat: {
      accounts: {
        // mnemonic,
        accounts: [privateKey],
      },
      chainId: chainIds.hardhat,
    },
    arbitrum: createConfig('arbitrum', 'https://arb1.arbitrum.io/rpc'),
    arbgoerli: createConfig(
      'arbgoerli',
      'https://endpoints.omniatech.io/v1/arbitrum/goerli/public'
    ),
    arbsep: createConfig('arbsep', 'https://sepolia-rollup.arbitrum.io/rpc'),
    base: createConfig('base', 'https://base-rpc.publicnode.com'),
    bsc: createConfig('bsc', 'https://bsc-dataseed.binance.org'),
    kcc: createConfig('kcc', 'https://rpc-mainnet.kcc.network'),
    polygon: createConfig(
      'polygon',
      'https://matic-mainnet.chainstacklabs.com'
    ),
    mainnet: createConfig('mainnet'),
    mode: createConfig('mode', 'https://mainnet.mode.network'),
    goerli: createConfig('goerli'),
    sepolia: createConfig('sepolia', 'https://ethereum-sepolia.publicnode.com'),
    opsep: createConfig('opsep', 'https://sepolia.optimism.io'),
  },
  paths: {
    artifacts: './artifacts',
    cache: './cache',
    sources: './contracts',
    tests: './test',
  },
  solidity: {
    version: '0.8.19',
    settings: {
      metadata: {
        // Not including the metadata hash
        // https://github.com/paulrberg/solidity-template/issues/31
        bytecodeHash: 'none',
      },
      // You should disable the optimizer when debugging
      // https://hardhat.org/hardhat-network/#solidity-optimizer-support
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5',
  },
}

// export default config;
module.exports.default = config

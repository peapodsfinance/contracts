const ethers = require('ethers')

// https://hardhat.org/hardhat-runner/plugins/nomicfoundation-hardhat-verify#complex-arguments
module.exports = [
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
  ),
]

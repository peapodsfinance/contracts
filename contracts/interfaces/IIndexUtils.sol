// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './IDecentralizedIndex.sol';

interface IIndexUtils {
  function addLPAndStake(
    IDecentralizedIndex indexFund,
    uint256 amountIdxTokens,
    address pairedLpTokenProvided,
    uint256 amtPairedLpTokenProvided,
    uint256 amountPairedLpTokenMin,
    uint256 slippage,
    uint256 deadline
  ) external payable returns (uint256 amountOut);
}

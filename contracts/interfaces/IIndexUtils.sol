// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IDecentralizedIndex.sol";

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

    function unstakeAndRemoveLP(
        IDecentralizedIndex indexFund,
        uint256 amountStakedTokens,
        uint256 minLPTokens,
        uint256 minPairedLpToken,
        uint256 deadline
    ) external;
}

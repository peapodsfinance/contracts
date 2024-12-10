// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IDecentralizedIndex.sol";

interface IIndexUtils_LEGACY {
    function addLPAndStake(
        IDecentralizedIndex _indexFund,
        uint256 _amountIdxTokens,
        address _pairedLpTokenProvided,
        uint256 _amtPairedLpTokenProvided,
        uint256 _amountPairedLpTokenMin,
        uint256 _slippage,
        uint256 _deadline
    ) external payable;

    function unstakeAndRemoveLP(
        IDecentralizedIndex _indexFund,
        uint256 _amountStakedTokens,
        uint256 _minLPTokens,
        uint256 _minPairedLpToken,
        uint256 _deadline
    ) external;
}

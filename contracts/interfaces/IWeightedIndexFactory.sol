// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IDecentralizedIndex.sol";

interface IWeightedIndexFactory {
    function deployPodAndLinkDependencies(
        string memory indexName,
        string memory indexSymbol,
        bytes memory baseConfig,
        bytes memory immutables
    ) external returns (address weightedIndex, address stakingPool, address tokenRewards);
}

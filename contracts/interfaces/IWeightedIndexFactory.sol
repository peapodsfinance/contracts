// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IDecentralizedIndex.sol";

interface IWeightedIndexFactory {
    function deployPodAndLinkDependencies(
        string memory indexName,
        string memory indexSymbol,
        IDecentralizedIndex.Config memory config,
        IDecentralizedIndex.Fees memory fees,
        address[] memory tokens,
        uint256[] memory weights,
        address stakeUserRestriction,
        bool leaveRewardsAsPairedLp,
        bytes memory immutables
    ) external returns (address weightedIndex, address stakingPool, address tokenRewards);
}

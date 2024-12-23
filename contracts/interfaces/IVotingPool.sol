// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/IStakingConversionFactor.sol";

interface IVotingPool {
    struct Asset {
        bool enabled;
        IStakingConversionFactor convFactor;
    }

    struct Stake {
        uint256 amtStaked;
        uint256 lockupPeriod;
        uint256 stakedToOutputFactor;
        uint256 stakedToOutputDenomenator;
        uint256 lastStaked;
    }

    event AddStake(address indexed user, address asset, uint256 amount);

    event UpdateUserState(address indexed user, address asset, uint256 conversionFactor, uint256 conversionDenomenator);

    event Unstake(address indexed user, address asset, uint256 amountBurned, uint256 amountAsset);

    function REWARDS() external view returns (address);

    function lockupPeriod() external view returns (uint256);

    function stake(address asset, uint256 amount) external;

    function unstake(address asset, uint256 amount) external;

    function processPreSwapFeesAndSwap() external; // noop to inherit pod rewards
}

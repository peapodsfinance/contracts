// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IDecentralizedIndex.sol";
import "./interfaces/IInitializeSelector.sol";
import "./interfaces/IStakingPoolToken.sol";
import "./interfaces/IWeightedIndexFactory.sol";

contract WeightedIndexFactory is Ownable, IWeightedIndexFactory {
    struct DeployedContracts {
        address weightedIndexImpl;
        address stakingPoolTokenImpl;
        address tokenRewardsImpl;
        address weightedIndexBeacon;
        address stakingPoolTokenBeacon;
        address tokenRewardsBeacon;
    }

    DeployedContracts public deployedContracts;

    event PodDeployed(address weightedIndexProxy, address stakingPoolTokenProxy, address tokenRewardsProxy);

    constructor() Ownable(_msgSender()) {}

    function setImplementationsAndBeacons(
        address weightedIndexImpl,
        address stakingPoolTokenImpl,
        address tokenRewardsImpl,
        address weightedIndexBeacon,
        address stakingPoolTokenBeacon,
        address tokenRewardsBeacon
    ) external onlyOwner {
        // Store implementation addresses
        deployedContracts.weightedIndexImpl = weightedIndexImpl;
        deployedContracts.stakingPoolTokenImpl = stakingPoolTokenImpl;
        deployedContracts.tokenRewardsImpl = tokenRewardsImpl;

        // Store beacon addresses
        deployedContracts.weightedIndexBeacon = weightedIndexBeacon;
        deployedContracts.stakingPoolTokenBeacon = stakingPoolTokenBeacon;
        deployedContracts.tokenRewardsBeacon = tokenRewardsBeacon;
    }

    function deployPodAndLinkDependencies(
        string memory indexName,
        string memory indexSymbol,
        bytes memory baseConfig,
        bytes memory immutables
    ) external override returns (address weightedIndex, address stakingPool, address tokenRewards) {
        require(
            deployedContracts.weightedIndexBeacon != address(0)
                && deployedContracts.stakingPoolTokenBeacon != address(0)
                && deployedContracts.tokenRewardsBeacon != address(0),
            "Beacons not deployed"
        );
        require(
            deployedContracts.weightedIndexImpl != address(0) && deployedContracts.stakingPoolTokenImpl != address(0)
                && deployedContracts.tokenRewardsImpl != address(0),
            "Implementations not deployed"
        );

        // Deploy WeightedIndex proxy
        bytes memory weightedIndexData = abi.encodeWithSelector(
            IInitializeSelector(deployedContracts.weightedIndexImpl).initializeSelector(),
            indexName,
            indexSymbol,
            baseConfig,
            immutables
        );
        weightedIndex = address(new BeaconProxy(deployedContracts.weightedIndexBeacon, weightedIndexData));

        (,,,, address stakeUserRestriction, bool leaveRewardsAsPairedLp) = abi.decode(
            baseConfig, (IDecentralizedIndex.Config, IDecentralizedIndex.Fees, address[], uint256[], address, bool)
        );

        // Deploy StakingPoolToken proxy
        bytes memory stakingPoolData = abi.encodeWithSelector(
            IInitializeSelector(deployedContracts.stakingPoolTokenImpl).initializeSelector(),
            string.concat("Staked ", indexName),
            string.concat("s", indexSymbol),
            weightedIndex,
            stakeUserRestriction,
            immutables
        );
        stakingPool = address(new BeaconProxy(deployedContracts.stakingPoolTokenBeacon, stakingPoolData));

        // Deploy TokenRewards proxy
        bytes memory tokenRewardsData = abi.encodeWithSelector(
            IInitializeSelector(deployedContracts.tokenRewardsImpl).initializeSelector(),
            weightedIndex,
            stakingPool,
            leaveRewardsAsPairedLp,
            immutables
        );
        tokenRewards = address(new BeaconProxy(deployedContracts.tokenRewardsBeacon, tokenRewardsData));

        // Link contracts together
        IDecentralizedIndex(payable(weightedIndex)).setLpStakingPool(stakingPool);
        IStakingPoolToken(stakingPool).setPoolRewards(tokenRewards);
        Ownable(stakingPool).transferOwnership(weightedIndex);
        if (!IDecentralizedIndex(payable(weightedIndex)).DEX_HANDLER().ASYNC_INITIALIZE()) {
            IDecentralizedIndex(payable(weightedIndex)).setup();
        }

        emit PodDeployed(weightedIndex, stakingPool, tokenRewards);
    }
}

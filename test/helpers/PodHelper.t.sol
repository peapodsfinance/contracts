// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../../contracts/interfaces/IDecentralizedIndex.sol";
import "../../contracts/interfaces/IDexAdapter.sol";
import "../../contracts/interfaces/IStakingPoolToken.sol";
import "../../contracts/interfaces/IV3TwapUtilities.sol";
import {IndexUtils} from "../../contracts/IndexUtils.sol";
import {StakingPoolToken} from "../../contracts/StakingPoolToken.sol";
import {TokenRewards} from "../../contracts/TokenRewards.sol";
import {WeightedIndex} from "../../contracts/WeightedIndex.sol";
import {WeightedIndexFactory} from "../../contracts/WeightedIndexFactory.sol";
import {RewardsWhitelist} from "../../contracts/RewardsWhitelist.sol";

contract PodHelperTest is Test {
    RewardsWhitelist _rewardsWhitelistSub;
    WeightedIndexFactory _podDeployerSub;

    function setUp() public virtual {
        _rewardsWhitelistSub = new RewardsWhitelist();
        _podDeployerSub = new WeightedIndexFactory();
        _deployImpAndBeacons(address(this));
    }

    function _deployImpAndBeacons(address _owner)
        internal
        returns (address pi, address spi, address tri, address pb, address spb, address trb)
    {
        pi = address(new WeightedIndex());
        pb = address(new UpgradeableBeacon(pi, _owner));

        spi = address(new StakingPoolToken());
        spb = address(new UpgradeableBeacon(spi, _owner));

        tri = address(new TokenRewards());
        trb = address(new UpgradeableBeacon(tri, _owner));
        _podDeployerSub.setImplementationsAndBeacons(pi, spi, tri, pb, spb, trb);
    }

    function _dupPodAndSeedLp(
        address _pod,
        address _pairedOverride,
        uint256 _pairedOverrideFactorMult,
        uint256 _pairedOverrideFactorDiv
    ) internal returns (address _newPod) {
        address pairedLpToken =
            _pairedOverride != address(0) ? _pairedOverride : IDecentralizedIndex(_pod).PAIRED_LP_TOKEN();

        IndexUtils _utils = new IndexUtils(
            IV3TwapUtilities(0x024ff47D552cB222b265D68C7aeB26E586D5229D),
            IDexAdapter(0x7686aa8B32AA9Eb135AC15a549ccd71976c878Bb)
        );

        address _underlying;
        (_underlying, _newPod) = _duplicatePod(_pod, pairedLpToken);

        address _lpStakingPool = IDecentralizedIndex(_pod).lpStakingPool();
        address _podV2Pool = IStakingPoolToken(_lpStakingPool).stakingToken();
        deal(
            _underlying,
            address(this),
            (IERC20(_pod).balanceOf(_podV2Pool) * 10 ** IERC20Metadata(_underlying).decimals())
                / 10 ** IERC20Metadata(_pod).decimals()
        );
        deal(
            pairedLpToken,
            address(this),
            (
                (_pairedOverrideFactorMult == 0 ? 1 : _pairedOverrideFactorMult)
                    * (
                        IERC20(IDecentralizedIndex(_pod).PAIRED_LP_TOKEN()).balanceOf(_podV2Pool)
                            * 10 ** IERC20Metadata(pairedLpToken).decimals()
                    )
            ) / 10 ** IERC20Metadata(IDecentralizedIndex(_pod).PAIRED_LP_TOKEN()).decimals()
                / (_pairedOverrideFactorDiv == 0 ? 1 : _pairedOverrideFactorDiv)
        );

        IERC20(_underlying).approve(_newPod, IERC20(_underlying).balanceOf(address(this)));
        IDecentralizedIndex(_newPod).bond(_underlying, IERC20(_underlying).balanceOf(address(this)), 0);

        IERC20(_newPod).approve(address(_utils), IERC20(_newPod).balanceOf(address(this)));
        IERC20(pairedLpToken).approve(address(_utils), IERC20(pairedLpToken).balanceOf(address(this)));
        _utils.addLPAndStake(
            IDecentralizedIndex(_newPod),
            IERC20(_newPod).balanceOf(address(this)),
            pairedLpToken,
            IERC20(pairedLpToken).balanceOf(address(this)),
            0,
            1000,
            block.timestamp
        );
    }

    function _duplicatePod(address _oldPod, address _pairedLpToken)
        internal
        returns (address _underlying, address _newPod)
    {
        IDecentralizedIndex.IndexAssetInfo[] memory _assets = IDecentralizedIndex(_oldPod).getAllAssets();
        _underlying = _assets[0].token;
        address[] memory _t = new address[](1);
        _t[0] = _underlying;
        uint256[] memory _w = new uint256[](1);
        _w[0] = 100;
        _newPod = _createPod(
            "Test",
            "pTEST",
            _getPodConfig(_oldPod),
            IDecentralizedIndex(_oldPod).fees(),
            _t,
            _w,
            address(0),
            false,
            _getImmutables(_pairedLpToken, 0x7686aa8B32AA9Eb135AC15a549ccd71976c878Bb)
        );
    }

    function _duplicatePod(address _oldPod, address _pairedLpToken, address[] memory _tokens, uint256[] memory _weights)
        internal
        returns (address _underlying, address _newPod)
    {
        IDecentralizedIndex.IndexAssetInfo[] memory _assets = IDecentralizedIndex(_oldPod).getAllAssets();
        _underlying = _assets[0].token;
        _newPod = _createPod(
            "Test",
            "pTEST",
            _getPodConfig(_oldPod),
            IDecentralizedIndex(_oldPod).fees(),
            _tokens,
            _weights,
            address(0),
            false,
            _getImmutables(_pairedLpToken, 0x7686aa8B32AA9Eb135AC15a549ccd71976c878Bb)
        );
    }

    function _createPod(
        string memory indexName,
        string memory indexSymbol,
        IDecentralizedIndex.Config memory config,
        IDecentralizedIndex.Fees memory fees,
        address[] memory tokens,
        uint256[] memory weights,
        address stakeUserRestriction,
        bool leaveRewardsAsPairedLp,
        bytes memory immutables
    ) internal returns (address newPod) {
        (newPod,,) = _podDeployerSub.deployPodAndLinkDependencies(
            indexName,
            indexSymbol,
            abi.encode(config, fees, tokens, weights, stakeUserRestriction, leaveRewardsAsPairedLp),
            immutables
        );
    }

    function _getImmutables(address _pairedLpToken, address _dexAdapter) internal view returns (bytes memory) {
        return abi.encode(
            _pairedLpToken,
            0x02f92800F57BCD74066F5709F1Daa1A4302Df875,
            0x6B175474E89094C44Da98b954EedeAC495271d0F,
            0x7d544DD34ABbE24C8832db27820Ff53C151e949b,
            address(_rewardsWhitelistSub),
            0x024ff47D552cB222b265D68C7aeB26E586D5229D,
            _dexAdapter
        );
    }

    function _getPodConfig(address _pod) internal view returns (IDecentralizedIndex.Config memory _c) {
        _c.partner = IDecentralizedIndex(_pod).partner();
    }
}

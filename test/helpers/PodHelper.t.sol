// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "../../contracts/interfaces/IDecentralizedIndex.sol";
import "../../contracts/interfaces/IDexAdapter.sol";
import "../../contracts/interfaces/IStakingPoolToken.sol";
import "../../contracts/interfaces/IV3TwapUtilities.sol";
import {IndexUtils} from "../../contracts/IndexUtils.sol";
import {WeightedIndex} from "../../contracts/WeightedIndex.sol";
import {RewardsWhitelist} from "../../contracts/RewardsWhitelist.sol";

contract PodHelperTest is Test {
    RewardsWhitelist _rewardsWhitelist;

    function setUp() public virtual {
        _rewardsWhitelist = new RewardsWhitelist();
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
        (_underlying, _newPod) = _createPod(_pod, pairedLpToken, 0x7686aa8B32AA9Eb135AC15a549ccd71976c878Bb);

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

    function _createPod(address _oldPod, address _pairedLpToken, address _dexAdapter)
        internal
        returns (address _underlying, address _newPod)
    {
        IDecentralizedIndex.IndexAssetInfo[] memory _assets = IDecentralizedIndex(_oldPod).getAllAssets();
        _underlying = _assets[0].token;
        IDecentralizedIndex.Config memory _c;
        _c.partner = IDecentralizedIndex(_oldPod).partner();
        IDecentralizedIndex.Fees memory _f = _getPodFees(_oldPod);
        address[] memory _t = new address[](1);
        _t[0] = address(_underlying);
        uint256[] memory _w = new uint256[](1);
        _w[0] = 100;
        _newPod = address(
            new WeightedIndex(
                "Test", "pTEST", _c, _f, _t, _w, false, false, _getImmutables(_pairedLpToken, _dexAdapter)
            )
        );
    }

    function _getImmutables(address _pairedLpToken, address _dexAdapter) internal view returns (bytes memory) {
        return abi.encode(
            _pairedLpToken,
            0x02f92800F57BCD74066F5709F1Daa1A4302Df875,
            0x6B175474E89094C44Da98b954EedeAC495271d0F,
            0x7d544DD34ABbE24C8832db27820Ff53C151e949b,
            address(_rewardsWhitelist),
            0x024ff47D552cB222b265D68C7aeB26E586D5229D,
            _dexAdapter
        );
    }

    function _getPodFees(address _pod) internal view returns (IDecentralizedIndex.Fees memory _f) {
        (uint16 _f0, uint16 _f1, uint16 _f2, uint16 _f3, uint16 _f4, uint16 _f5) = WeightedIndex(payable(_pod)).fees();
        _f.burn = _f0;
        _f.bond = _f1;
        _f.debond = _f2;
        _f.buy = _f3;
        _f.sell = _f4;
        _f.partner = _f5;
    }
}

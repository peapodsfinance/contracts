// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {FuzzSetup} from "../FuzzSetup.sol";

import {FraxlendPairCore} from "../modules/fraxlend/FraxlendPairCore.sol";
import {FraxlendPair} from "../modules/fraxlend/FraxlendPair.sol";
import {StakingPoolToken} from "../../../contracts/StakingPoolToken.sol";
import {WeightedIndex} from "../../../contracts/WeightedIndex.sol";
import {AutoCompoundingPodLp} from "../../../contracts/AutoCompoundingPodLp.sol";

contract BeforeAfter is FuzzSetup {

    struct LavVars {
        uint256 userShareBalance;
        uint256 receiverShareBalance;
        uint256 totalSupply;
        uint256 totalAssets;
    }

    LavVars internal _beforeLav;
    LavVars internal _afterLav;

    function __beforeLav(address user, address receiver) internal {
        _beforeLav.userShareBalance = _lendingAssetVault.balanceOf(user);
        _beforeLav.receiverShareBalance = _lendingAssetVault.balanceOf(receiver);
        _beforeLav.totalSupply = _lendingAssetVault.totalSupply();
        _beforeLav.totalAssets = _lendingAssetVault.totalAssets();
    }

    function __afterLav(address user, address receiver) internal {
        _afterLav.userShareBalance = _lendingAssetVault.balanceOf(user);
        _afterLav.receiverShareBalance = _lendingAssetVault.balanceOf(receiver);
        _afterLav.totalSupply = _lendingAssetVault.totalSupply();
        _afterLav.totalAssets = _lendingAssetVault.totalAssets();
    }

    struct LeverageManagerVars {
        uint256 vaultUtilization;
        uint256 totalAvailableAssets;
        uint256 totalAssetsUtilized;
        uint256 cbr;
        uint64 utilizationRate;
        uint256 totalBorrowAmount;
        uint256 totalBorrowShares;
        uint256 spTotalSupply;
        uint256 aspTotalSupply;
        uint256 custodianCollateralBalance;
        uint256 custodianBorrowShares;
    }

    LeverageManagerVars internal _beforeLM;
    LeverageManagerVars internal _afterLM;

    function __beforeLM(address vault, address pod, address aspTKN, address custodian) internal {
        _beforeLM.vaultUtilization = _lendingAssetVault.vaultUtilization(vault);
        _beforeLM.totalAvailableAssets = _lendingAssetVault.totalAvailableAssets();
        _beforeLM.totalAssetsUtilized = _lendingAssetVault.totalAssetsUtilized();
        _beforeLM.cbr = _cbrGhost();
        ( , , , , _beforeLM.utilizationRate) = FraxlendPairCore(vault).currentRateInfo();
        ( , , _beforeLM.totalBorrowAmount, _beforeLM.totalBorrowShares, ) = FraxlendPair(vault).getPairAccounting();
        _beforeLM.spTotalSupply = StakingPoolToken(WeightedIndex(payable(pod)).lpStakingPool()).totalSupply();
        _beforeLM.aspTotalSupply = AutoCompoundingPodLp(aspTKN).totalSupply();
        _beforeLM.custodianCollateralBalance = FraxlendPair(vault).userCollateralBalance(custodian);
        _beforeLM.custodianBorrowShares = FraxlendPair(vault).userBorrowShares(custodian);
    }

    function __afterLM(address vault, address pod, address aspTKN, address custodian) internal {
        _afterLM.vaultUtilization = _lendingAssetVault.vaultUtilization(vault);
        _afterLM.totalAvailableAssets = _lendingAssetVault.totalAvailableAssets();
        _afterLM.totalAssetsUtilized = _lendingAssetVault.totalAssetsUtilized();
        _afterLM.cbr = _cbrGhost();
        ( , , , , _afterLM.utilizationRate) = FraxlendPairCore(vault).currentRateInfo();
        ( , , _afterLM.totalBorrowAmount, _afterLM.totalBorrowShares, ) = FraxlendPair(vault).getPairAccounting();
        _afterLM.spTotalSupply = StakingPoolToken(WeightedIndex(payable(pod)).lpStakingPool()).totalSupply();
        _afterLM.aspTotalSupply = AutoCompoundingPodLp(aspTKN).totalSupply();
        _afterLM.custodianCollateralBalance = FraxlendPair(vault).userCollateralBalance(custodian);
        _afterLM.custodianBorrowShares = FraxlendPair(vault).userBorrowShares(custodian);
    }

    function _cbrGhost() internal returns (uint256) {
        uint256 totalSupply = _lendingAssetVault.totalSupply();
        return totalSupply == 0 ? PRECISION : (PRECISION * _lendingAssetVault.totalAssets()) / totalSupply;
    }
}
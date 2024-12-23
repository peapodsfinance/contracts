// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {FuzzSetup} from "../FuzzSetup.sol";

import {FraxlendPairCore} from "../modules/fraxlend/FraxlendPairCore.sol";
import {FraxlendPair} from "../modules/fraxlend/FraxlendPair.sol";
import {IFraxlendPair} from "../modules/fraxlend/interfaces/IFraxlendPair.sol";
import {StakingPoolToken} from "../../../contracts/StakingPoolToken.sol";
import {WeightedIndex} from "../../../contracts/WeightedIndex.sol";
import {AutoCompoundingPodLp} from "../../../contracts/AutoCompoundingPodLp.sol";
import {VaultAccount, VaultAccountingLibrary} from "../modules/fraxlend/libraries/VaultAccount.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BeforeAfter is FuzzSetup {
    struct LavVars {
        uint256 userShareBalance;
        uint256 receiverShareBalance;
        uint256 totalSupply;
        uint256 totalAssets;
        uint256 vaultUtilization;
    }

    LavVars internal _beforeLav;
    LavVars internal _afterLav;

    function __beforeLav(address user, address receiver, address vault) internal {
        _beforeLav.userShareBalance = _lendingAssetVault.balanceOf(user);
        _beforeLav.receiverShareBalance = _lendingAssetVault.balanceOf(receiver);
        _beforeLav.totalSupply = _lendingAssetVault.totalSupply();
        _beforeLav.totalAssets = _lendingAssetVault.totalAssets();
        _beforeLav.vaultUtilization = _lendingAssetVault.vaultUtilization(vault);
    }

    function __afterLav(address user, address receiver, address vault) internal {
        _afterLav.userShareBalance = _lendingAssetVault.balanceOf(user);
        _afterLav.receiverShareBalance = _lendingAssetVault.balanceOf(receiver);
        _afterLav.totalSupply = _lendingAssetVault.totalSupply();
        _afterLav.totalAssets = _lendingAssetVault.totalAssets();
        _afterLav.vaultUtilization = _lendingAssetVault.vaultUtilization(vault);
    }

    struct LeverageManagerVars {
        uint256 vaultUtilization;
        uint256 totalAvailableAssets;
        uint256 totalAssetsUtilized;
        uint256 totalAssetsLAV;
        uint256 cbr;
        uint256 utilizationRate;
        uint256 totalBorrowAmount;
        uint256 totalBorrowShares;
        uint256 spTotalSupply;
        uint256 aspTotalSupply;
        uint256 custodianCollateralBalance;
        uint256 custodianBorrowShares;
        uint256 custodianLTV;
        uint256 pairAssetApproval;
        uint256 podLpApproval;
        uint256 podLpIndexApproval;
        uint256 podDexApproval;
        uint256 podIndexApproval;
        uint256 spTKNApproval;
        uint256 spTKNIndexApproval;
        uint256 custodianPairApproval;
    }

    LeverageManagerVars internal _beforeLM;
    LeverageManagerVars internal _afterLM;

    function __beforeLM(address vault, address pod, address aspTKN, address custodian) internal {
        _beforeLM.vaultUtilization = _lendingAssetVault.vaultUtilization(vault);
        _beforeLM.totalAvailableAssets = _lendingAssetVault.totalAvailableAssets();
        _beforeLM.totalAssetsUtilized = _lendingAssetVault.totalAssetsUtilized();
        _beforeLM.totalAssetsLAV = _lendingAssetVault.totalAssets();
        _beforeLM.cbr = _cbrGhost();
        (uint128 borrowAmount,) = FraxlendPairCore(vault).totalBorrow();
        (uint128 assetAmount, uint128 assetShares) = FraxlendPairCore(vault).totalAsset();
        VaultAccount memory vaultAccount = VaultAccount(assetAmount, assetShares);
        uint256 totalAmount = VaultAccountingLibrary.totalAmount(vaultAccount, address(_lendingAssetVault));
        _beforeLM.utilizationRate = (1e5 * borrowAmount) / totalAmount;
        (,, _beforeLM.totalBorrowAmount, _beforeLM.totalBorrowShares,) = FraxlendPair(vault).getPairAccounting();
        _beforeLM.spTotalSupply = StakingPoolToken(WeightedIndex(payable(pod)).lpStakingPool()).totalSupply();
        _beforeLM.aspTotalSupply = AutoCompoundingPodLp(aspTKN).totalSupply();
        _beforeLM.custodianCollateralBalance = FraxlendPair(vault).userCollateralBalance(custodian);
        _beforeLM.custodianBorrowShares = FraxlendPair(vault).userBorrowShares(custodian);
        _beforeLM.custodianLTV = _ltvGhost(vault, custodian);
    }

    function __afterLM(address vault, address pod, address aspTKN, address custodian) internal {
        _afterLM.vaultUtilization = _lendingAssetVault.vaultUtilization(vault);
        _afterLM.totalAvailableAssets = _lendingAssetVault.totalAvailableAssets();
        _afterLM.totalAssetsUtilized = _lendingAssetVault.totalAssetsUtilized();
        _afterLM.totalAssetsLAV = _lendingAssetVault.totalAssets();
        _afterLM.cbr = _cbrGhost();
        (uint128 borrowAmount,) = FraxlendPairCore(vault).totalBorrow();
        (uint128 assetAmount, uint128 assetShares) = FraxlendPairCore(vault).totalAsset();
        VaultAccount memory vaultAccount = VaultAccount(assetAmount, assetShares);
        uint256 totalAmount = VaultAccountingLibrary.totalAmount(vaultAccount, address(_lendingAssetVault));
        _afterLM.utilizationRate = (1e5 * borrowAmount) / totalAmount;
        (,, _afterLM.totalBorrowAmount, _afterLM.totalBorrowShares,) = FraxlendPair(vault).getPairAccounting();
        _afterLM.spTotalSupply = StakingPoolToken(WeightedIndex(payable(pod)).lpStakingPool()).totalSupply();
        _afterLM.aspTotalSupply = AutoCompoundingPodLp(aspTKN).totalSupply();
        _afterLM.custodianCollateralBalance = FraxlendPair(vault).userCollateralBalance(custodian);
        _afterLM.custodianBorrowShares = FraxlendPair(vault).userBorrowShares(custodian);
        _afterLM.custodianLTV = _ltvGhost(vault, custodian);
        _afterLM.pairAssetApproval = IERC20(IFraxlendPair(vault).asset()).allowance(vault, address(_lendingAssetVault));
        _afterLM.podLpApproval =
            IERC20(WeightedIndex(payable(pod)).PAIRED_LP_TOKEN()).allowance(address(_leverageManager), vault);
        _afterLM.podLpIndexApproval = IERC20(WeightedIndex(payable(pod)).PAIRED_LP_TOKEN()).allowance(
            address(_leverageManager), address(_indexUtils)
        );
        _afterLM.podDexApproval = IERC20(pod).allowance(address(_leverageManager), address(_dexAdapter));
        _afterLM.podIndexApproval = IERC20(pod).allowance(address(_leverageManager), address(_indexUtils));
        _afterLM.spTKNApproval =
            StakingPoolToken(WeightedIndex(payable(pod)).lpStakingPool()).allowance(address(_leverageManager), aspTKN);
        _afterLM.spTKNIndexApproval = StakingPoolToken(WeightedIndex(payable(pod)).lpStakingPool()).allowance(
            address(_leverageManager), address(_indexUtils)
        );
        _afterLM.custodianPairApproval = IERC20(IFraxlendPair(vault).collateralContract()).allowance(custodian, vault);
    }

    struct AspTknVars {
        uint256 spTotalSupply;
        uint256 aspTotalSupply;
        uint256 spUserBalance;
        uint256 spReceiverBalance;
        uint256 userAssetApproval;
        uint256 aspRewardApproval;
        uint256 pairedLpApproval;
        uint256 podIndexUtilsApproval;
        uint256 pairedLpIndexApproval;
    }

    AspTknVars internal _beforeASP;
    AspTknVars internal _afterASP;

    function __beforeAsp(AutoCompoundingPodLp aspTKN, StakingPoolToken spTKN, address user, address receiver)
        internal
    {
        _beforeASP.spTotalSupply = spTKN.totalSupply();
        _beforeASP.aspTotalSupply = aspTKN.totalSupply();
        _beforeASP.spUserBalance = spTKN.balanceOf(user);
        _beforeASP.spReceiverBalance = spTKN.balanceOf(receiver);
    }

    function __afterAsp(AutoCompoundingPodLp aspTKN, StakingPoolToken spTKN, address user, address receiver) internal {
        _afterASP.spTotalSupply = spTKN.totalSupply();
        _afterASP.aspTotalSupply = aspTKN.totalSupply();
        _afterASP.spUserBalance = spTKN.balanceOf(user);
        _afterASP.spReceiverBalance = spTKN.balanceOf(receiver);
        _afterASP.userAssetApproval = IERC20(aspTKN.asset()).allowance(user, address(aspTKN));
        _afterASP.aspRewardApproval = _peas.allowance(address(aspTKN), address(_dexAdapter));
        _afterASP.pairedLpApproval =
            IERC20(aspTKN.pod().PAIRED_LP_TOKEN()).allowance(address(aspTKN), address(_dexAdapter));
        _afterASP.podIndexUtilsApproval = IERC20(address(aspTKN.pod())).allowance(address(aspTKN), address(_indexUtils));
        _afterASP.pairedLpIndexApproval =
            IERC20(aspTKN.pod().PAIRED_LP_TOKEN()).allowance(address(aspTKN), address(_indexUtils));
    }

    struct FraxVars {
        uint256 userLTV;
    }

    FraxVars internal _beforeFrax;
    FraxVars internal _afterFrax;

    function __beforeFrax(address lendingPair, address user) internal {
        _beforeFrax.userLTV = _ltvGhost(lendingPair, user);
    }

    function __afterFrax(address lendingPair, address user) internal {
        _afterFrax.userLTV = _ltvGhost(lendingPair, user);
    }

    function _cbrGhost() internal view returns (uint256) {
        uint256 totalSupply = _lendingAssetVault.totalSupply();
        return totalSupply == 0 ? PRECISION : (PRECISION * _lendingAssetVault.totalAssets()) / totalSupply;
    }

    function _ltvGhost(address lendingPair, address borrower) internal view returns (uint256) {
        (,,,, uint256 highExchangeRate) = FraxlendPair(lendingPair).exchangeRateInfo();

        uint256 _borrowerAmount = VaultAccountingLibrary.toAmount(
            IFraxlendPair(lendingPair).totalBorrow(), IFraxlendPair(lendingPair).userBorrowShares(borrower), true
        );
        if (_borrowerAmount == 0) return 0;
        uint256 _collateralAmount = IFraxlendPair(lendingPair).userCollateralBalance(borrower);
        if (_collateralAmount == 0) return 0;
        return (
            ((_borrowerAmount * highExchangeRate) / FraxlendPair(lendingPair).EXCHANGE_PRECISION())
                * FraxlendPair(lendingPair).LTV_PRECISION()
        ) / _collateralAmount;
    }
}

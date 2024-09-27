// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {BeforeAfter} from "./BeforeAfter.sol";

import {FraxlendPair} from "../modules/fraxlend/FraxlendPair.sol";
import {FraxlendPairCore} from "../modules/fraxlend/FraxlendPairCore.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Properties is BeforeAfter {
    
    function invariant_POD_1() internal { 
        fl.t(false, "POD-1: LeverageManager::_acquireBorrowTokenForRepayment should never Uniswap revert");
    }

    function invariant_POD_2(uint256 shares) internal {
        // LendingAssetVault::deposit share balance of receiver should increase
        // LendingAssetVault::mint share balance of receiver should increase
        fl.eq(
            _afterLav.receiverShareBalance,
            _beforeLav.receiverShareBalance + shares,
            "POD-2: LendingAssetVault::deposit/mint share balance of receiver should increase"
        );
    }

    function invariant_POD_3(uint256 shares) internal {
        // LendingAssetVault::withdraw share balance of user should decrease
        // LendingAssetVault::redeem share balance of user should decrease
        fl.eq(
            _afterLav.userShareBalance,
            _beforeLav.userShareBalance - shares,
            "POD-3: LendingAssetVault::withdraw/redeem share balance of user should decrease"
        );
    }

    function invariant_POD_4(FraxlendPair fraxPair) internal {
        // LendingAssetVault::vaultUtilization[_vault] 
        // vaultUtilization[_vault] == FraxLend.convertToAssets(LAV shares) post-update
        // @TODO add POD_4 where it needs to go
        assertApproxEq(
            _afterLM.vaultUtilization,
            fraxPair.convertToAssets(fraxPair.balanceOf(address(_lendingAssetVault))),
            10000,
            "POD-4: vaultUtilization[_vault] == FraxLend.convertToAssets(LAV shares) post-update"
        );
    }

    function invariant_POD_5() public {
        // LendingAssetVault::totalAssetsUtilized  totalAssetsUtilized == sum(all vault utilizations)
        uint256 utilizationSum;
        for (uint256 i; i < _fraxPairs.length; i++) {
            utilizationSum += _lendingAssetVault.vaultUtilization(address(_fraxPairs[i]));
        }

        fl.eq(
            utilizationSum,
            _lendingAssetVault.totalAssetsUtilized(),
            "POD-5: LendingAssetVault::totalAssetsUtilized totalAssetsUtilized == sum(all vault utilizations)"
        );
    }

    function invariant_POD_6() internal {
        // LendingAssetVault::whitelistDeposit totalAvailableAssets() should increase
        fl.gte(
            _afterLM.totalAvailableAssets,
            _beforeLM.totalAvailableAssets,
            "POD-6: LendingAssetVault::whitelistDeposit totalAvailableAssets() should increase"
        );
    }

    function invariant_POD_7(uint256 assets) internal {
        // LendingAssetVault::whitelistDeposit vault utilization should decrease accurately
        fl.eq(
            _afterLM.vaultUtilization,
            _beforeLM.vaultUtilization - assets,
            "POD-7: LendingAssetVault::whitelistDeposit vault utilization should decrease accurately"
        );
    }

    function invariant_POD_8(uint256 assets) internal {
        // LendingAssetVault::whitelistDeposit total utilization should decrease accurately
        fl.eq(
            _afterLM.totalAssetsUtilized,
            _beforeLM.totalAssetsUtilized - assets,
            "POD-8: LendingAssetVault::whitelistDeposit total utilization should decrease accurately"
        );
    }

    function invariant_POD_9() internal {
        // LendingAssetVault::whitelistWithdraw totalAvailableAssets() should decrease
        fl.lte(
            _afterLM.totalAvailableAssets,
            _beforeLM.totalAvailableAssets,
            "POD-9: LendingAssetVault::whitelistWithdrawtotalAvailableAssets() should decrease"
        );
    }

    function invariant_POD_10(uint256 assets) internal {
        // LendingAssetVault::whitelistWithdraw vault utilization should increase accurately
        fl.eq(
            _afterLM.vaultUtilization,
            _beforeLM.vaultUtilization + assets,
            "POD-10: LendingAssetVault::whitelistWithdraw vault utilization should increase accurately"
        );
    }

    function invariant_POD_11(uint256 assets) internal {
        // LendingAssetVault::whitelistWithdraw total utilization should increase accurately
        fl.eq(
            _afterLM.totalAssetsUtilized,
            _beforeLM.totalAssetsUtilized + assets,
            "POD-11: LendingAssetVault::whitelistWithdraw total utilization should increase accurately"
        );
    }

    // function invariant_POD_12() public {
    //     // LendingAssetVault::global totalAssets == sum(deposits,  functiondonate calls, total utilization)
    //     fl.log("DONAtiONS", donatedAmount);
    //     fl.log("lavDeposits", lavDeposits);
    //     fl.log("totalAssetsUtilized", _lendingAssetVault.totalAssetsUtilized());
    //     fl.log("totalAssets", _lendingAssetVault.totalAssets());
    //     assertApproxEq(
    //         donatedAmount + lavDeposits + _lendingAssetVault.totalAssetsUtilized(),
    //         _lendingAssetVault.totalAssets(),
    //         10000,
    //         "POD-12: LendingAssetVault::global totalAssets == sum(deposits,  functiondonate calls, total utilization)"
    //     );
    // }

    function invariant_POD_13(uint256 actualAmount, uint256 maxAmount) internal {
        // LendingAssetVault::withdraw/redeem User can't withdraw more than their share of total assets
        fl.lte(
            actualAmount,
            maxAmount,
            "POD-13: LendingAssetVault::withdraw/redeem User can't withdraw more than their share of total assets"
        );
    }
 
    function invariant_POD_14(uint256 assets) internal {
        // LendingAssetVault::donate Post-donation shares shouldn't have increased, 
        // but totalAssets should have by donated amount
        // assertApproxEq(
        //     _afterLav.totalSupply,
        //     _beforeLav.totalSupply,
        //     1,
        //     "POD-14a: LendingAssetVault::donate Post-donation shares shouldn't have increased, but totalAssets should have by donated amount"
        // );
        fl.gte(
            _afterLav.totalAssets,
            _beforeLav.totalAssets + assets,
            "POD-14b: LendingAssetVault::donate Post-donation shares shouldn't have increased, but totalAssets should have by donated amount"
        );
    }

    function invariant_POD_15() public {
        // LendingAssetVault::global FraxLend vault should never more assets lent to it from the LAV that the allotted _vaultMaxPerc 
        // e.g. convertToAssets(LAV fToken share balance) <= totalAssets * vault pct
        for (uint256 i; i < _fraxPairs.length; i++) {
            fl.lte(
                _lendingAssetVault.vaultUtilization(address(_fraxPairs[i])),
                _lendingAssetVault.totalAssets() * 2500,
                "POD-15: FraxLend vault should never more assets lent to it from the LAV that the allotted _vaultMaxPerc"
            );
        }
    }

    // function invariant_POD_16() internal {
    //     // LendingAssetVault::whitelistDeposit and whitelistWithdraw  _cbr() should not change after a whitelistDeposit 
    //     // and whitelistWithdraw since the burn/mint should be proportional.
    //     fl.eq(
    //         _afterLM.cbr,
    //         _beforeLM.cbr,
    //         "POD-16: LendingAssetVault::whitelistDeposit and whitelistWithdraw  _cbr() should not change after a whitelistDeposit/Withdraw"
    //     );
    // }

    function invariant_POD_17() internal {
        // LendingAssetVault::whitelistDeposit Post-state utilization rate in FraxLend should have decreased (called by repayAsset in FraxLend)
        // (utilization rate retrieved from currentRateInfo public var)
        fl.lte(
            _afterLM.utilizationRate,
            _beforeLM.utilizationRate,
            "POD-17: LendingAssetVault::whitelistDeposit Post-state utilization rate in FraxLend should have decreased"
        );
        // @TODO will addInterest affect this???
    }

    function invariant_POD_18() internal {
        // LendingAssetVault::whitelistWithdraw Post-state utilization rate in FraxLend should have increased or not changed 
        // (if called within from a redeem no change, increase if called from borrowAsset)
        // @TODO make sure this is in all the ffraxlend calls
        fl.gte(
            _afterLM.utilizationRate,
            _beforeLM.utilizationRate,
            "POD-18: LendingAssetVault::whitelistWithdraw Post-state utilization rate in FraxLend should have increased or not changed "
        );
    }
 
    function invariant_POD_19() internal {
        // LeverageManager::addLeverage Post adding leverage, there totalBorrow amount and shares,
        //  as well as utilization should increase in Fraxlend
        fl.gt(
            _afterLM.totalBorrowAmount,
            _beforeLM.totalBorrowAmount,
            "POD-19a: LeverageManager::addLeverage Post adding leverage, there totalBorrow amount and shares should increase"
        );
        fl.gt(
            _afterLM.totalBorrowShares,
            _beforeLM.totalBorrowShares,
            "POD-19b: LeverageManager::addLeverage Post adding leverage, there totalBorrow amount and shares should increase"
        );
    }

    function invariant_POD_20() internal {
        // LeverageManager::removeLeverage Post removing leverage, there totalBorrow amount and shares,
        // as well as utilization should decrease in Fraxlend
        fl.lt(
            _afterLM.totalBorrowAmount,
            _beforeLM.totalBorrowAmount,
            "POD-20a: LeverageManager::removeLeverage Post removing leverage, there totalBorrow amount and shares should decrease"
        );
        fl.lt(
            _afterLM.totalBorrowShares,
            _beforeLM.totalBorrowShares,
            "POD-20b: LeverageManager::removeLeverage Post removing leverage, there totalBorrow amount and shares should decrease"
        );
    }

    // I believe custodian doesn't hold balance of aspTKNs. All of it should be deposited into Fraxlend.

    // thanks for the catch userCollateralBalance should increase/decrease respectively. 

    function invariant_POD_21() internal {
        // LeverageManager::addLeverage Post adding leverage, there should be a higher supply of spTKNs (StakingPoolToken) and aspTKNS (AutoCompoundingPodLp), and 
        // the custodian for the position should have a higher userCollateralBalance
        fl.gt(
            _afterLM.spTotalSupply,
            _beforeLM.spTotalSupply,
            "POD-21: Post adding leverage, there should be a higher supply of spTKNs (StakingPoolToken)"
        );
    }

    function invariant_POD_22() internal {
        // LeverageManager::addLeverage Post adding leverage, there should be a higher supply of spTKNs (StakingPoolToken) and aspTKNS (AutoCompoundingPodLp), and 
        // the custodian for the position should have a higher userCollateralBalance
        fl.gt(
            _afterLM.aspTotalSupply,
            _beforeLM.aspTotalSupply,
            "POD-22: Post adding leverage, there should be a higher supply of aspTKNs (AutoCompoundingPodLp)"
        );
    }

    function invariant_POD_23() internal {
        // LeverageManager::addLeverage Post adding leverage, there should be a higher supply of spTKNs (StakingPoolToken) and aspTKNS (AutoCompoundingPodLp), and 
        // the custodian for the position should have a higher userCollateralBalance
        fl.gt(
            _afterLM.custodianCollateralBalance,
            _beforeLM.custodianCollateralBalance,
            "POD-23: Post adding leverage, the custodian for the position should have a higher userCollateralBalance"
        );
    }

    function invariant_POD_24() internal {
        // LeverageManager::removeLeverage Post removing leverage, there should be a lower supply of spTKNs (StakingPoolToken) and aspTKNS (AutoCompoundingPodLp), and 
        // the custodion for the position should have a lower userCollateralBalance of aspTKNS in FraxLend
        fl.lt(
            _afterLM.spTotalSupply,
            _beforeLM.spTotalSupply,
            "POD-24: Post removing leverage, there should be a lower supply of spTKNs (StakingPoolToken)"
        );
    }

    function invariant_POD_25() internal {
        // LeverageManager::removeLeverage Post removing leverage, there should be a lower supply of spTKNs (StakingPoolToken) and aspTKNS (AutoCompoundingPodLp), and 
        // the custodion for the position should have a lower userCollateralBalance of aspTKNS in FraxLend
        fl.lt(
            _afterLM.aspTotalSupply,
            _beforeLM.aspTotalSupply,
            "POD-25: Post removing leverage, there should be a lower supply of aspTKNs (AutoCompoundingPodLp)"
        );
    }

    function invariant_POD_26() internal {
        // LeverageManager::removeLeverage Post removing leverage, there should be a lower supply of spTKNs (StakingPoolToken) and aspTKNS (AutoCompoundingPodLp), and 
        // the custodion for the position should have a lower userCollateralBalance of aspTKNS in FraxLend
        fl.lt(
            _afterLM.custodianCollateralBalance,
            _beforeLM.custodianCollateralBalance,
            "POD-26: Post removing leverage, the custodian for the position should have a lower userCollateralBalance"
        );
    }
 
    // function invariant_POD_27() public {
    //     // LendingAssetVault::global. _totalAssetsAvailable() should never be more than the 
    //     // sum of user deposits into the LAV
    //     // @note lavDeposits contains deposited amount
    //     assertApproxLte(
    //         _lendingAssetVault.totalAvailableAssets(),
    //         lavDeposits,
    //         1,
    //         "POD-27: LendingAssetVault::global. _totalAssetsAvailable() should never be more than the sum of user deposits into the LAV"
    //     );
    // }

    function invariant_POD_28() internal {
        // Fraxlend should not experience overflow revert
        fl.t(false, "Fraxlend should not experience overflow revert");
    }

    function invariant_POD_29() internal {
        // FraxLend: cbr change with one large update == cbr change with multiple, smaller updates
    }

    function invariant_POD_30() public {
        // IERC20(pod).balanceOf(leverageManager) == 0, IERC20(pairedLpToken).balanceOf(leverageManager) == 0
        for (uint256 i; i < _pods.length; i++) {
            fl.eq(
                _pods[i].balanceOf(address(_leverageManager)),
                0,
                "POD-30a: LeverageManager contract should never hold any token balances"
            );
            fl.eq(
                IERC20(_pods[i].PAIRED_LP_TOKEN()).balanceOf(address(_leverageManager)),
                0,
                "POD-30b: LeverageManager contract should never hold any token balances"
            );
        }
    }

    function invariant_POD_31() public {
        // FraxlendPair.totalAsset includes both direct deposits and external vault deposits. 
        // Therefore, it shouuld always be greater or equal to vaultUtilization mapping tracked in LendingAssetVault
        for (uint256 i; i < _fraxPairs.length; i++) {
            (uint128 pairTotalAssets, ) = FraxlendPairCore(address(_fraxPairs[i])).totalAsset();
            fl.gte(
                uint256(pairTotalAssets),
                _lendingAssetVault.vaultUtilization(address(_fraxPairs[i])),
                "POD-31: FraxlendPair.totalAsset should be greater or equal to vaultUtilization (LendingAssetVault)"
            );
        }
    }

    function invariant_POD_32() public {
        // totalAssets must be greater than totalAssetUtilized
        fl.gte(
            _lendingAssetVault.totalAssets(),
            _lendingAssetVault.totalAssetsUtilized(),
            "POD-32: totalAssets must be greater than totalAssetUtilized"
        );
    }

    function invariant_POD_33() internal {
        // repayAsset should not lead to to insolvency
        fl.t(false, "POD-33: repayAsset should not lead to to insolvency");
    }

    // Workflow modifier cannot be left open
    // Voting pool balance + staking pool balance should equal token reward shares
}
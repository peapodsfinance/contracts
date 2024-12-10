// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {BeforeAfter} from "./BeforeAfter.sol";

import {StakingPoolToken} from "../../../contracts/StakingPoolToken.sol";
import {TokenRewards} from "../../../contracts/TokenRewards.sol";

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
        assertApproxEq(
            _lendingAssetVault.vaultUtilization(address(fraxPair)),
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

    function invariant_POD_12() public {
        // LendingAssetVault::global total assets == sum(deposits + donations + interest accrued - withdrawals)
        assertApproxEq(
            lavDeposits,
            _lendingAssetVault.totalAssets(),
            1,
            "POD-12: LendingAssetVault::global total assets == sum(deposits + donations + interest accrued - withdrawals)"
        );
    }

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
        assertApproxEq(
            _afterLav.totalSupply,
            _beforeLav.totalSupply,
            1,
            "POD-14a: LendingAssetVault::donate Post-donation shares shouldn't have increased, but totalAssets should have by donated amount"
        );
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
                _lendingAssetVault.totalAssets() * _fraxPercentages[i],
                "POD-15: FraxLend vault should never more assets lent to it from the LAV that the allotted _vaultMaxPerc"
            );
        }
    }

    function invariant_POD_16() internal {
        // LendingAssetVault::whitelistDeposit Post-state utilization rate in FraxLend should have decreased (called by repayAsset in FraxLend)
        // (utilization rate retrieved from currentRateInfo public var)
        fl.lte(
            _afterLM.utilizationRate,
            _beforeLM.utilizationRate,
            "POD-16: LendingAssetVault::whitelistDeposit Post-state utilization rate in FraxLend should have decreased"
        );
    }

    function invariant_POD_17() internal {
        // LendingAssetVault::whitelistWithdraw Post-state utilization rate in FraxLend should have increased or not changed
        // (if called within from a redeem no change, increase if called from borrowAsset)
        fl.gte(
            _afterLM.utilizationRate,
            _beforeLM.utilizationRate,
            "POD-17: LendingAssetVault::whitelistWithdraw Post-state utilization rate in FraxLend should have increased or not changed "
        );
    }

    function invariant_POD_18() internal {
        // LeverageManager::addLeverage Post adding leverage, there totalBorrow amount and shares,
        //  as well as utilization should increase in Fraxlend
        fl.gt(
            _afterLM.totalBorrowAmount,
            _beforeLM.totalBorrowAmount,
            "POD-18a: LeverageManager::addLeverage Post adding leverage, there totalBorrow amount and shares should increase"
        );
        fl.gt(
            _afterLM.totalBorrowShares,
            _beforeLM.totalBorrowShares,
            "POD-18b: LeverageManager::addLeverage Post adding leverage, there totalBorrow amount and shares should increase"
        );
    }

    function invariant_POD_19() internal {
        // LeverageManager::removeLeverage Post removing leverage, there totalBorrow amount and shares,
        // as well as utilization should decrease in Fraxlend
        fl.lt(
            _afterLM.totalBorrowAmount,
            _beforeLM.totalBorrowAmount,
            "POD-19a: LeverageManager::removeLeverage Post removing leverage, there totalBorrow amount and shares should decrease"
        );
        fl.lt(
            _afterLM.totalBorrowShares,
            _beforeLM.totalBorrowShares,
            "POD-19b: LeverageManager::removeLeverage Post removing leverage, there totalBorrow amount and shares should decrease"
        );
    }

    function invariant_POD_20() internal {
        // LeverageManager::addLeverage Post adding leverage, there should be a higher supply of spTKNs (StakingPoolToken) and aspTKNS (AutoCompoundingPodLp), and
        // the custodian for the position should have a higher userCollateralBalance
        fl.gt(
            _afterLM.spTotalSupply,
            _beforeLM.spTotalSupply,
            "POD-20: Post adding leverage, there should be a higher supply of spTKNs (StakingPoolToken)"
        );
    }

    function invariant_POD_21() internal {
        // LeverageManager::addLeverage Post adding leverage, there should be a higher supply of spTKNs (StakingPoolToken) and aspTKNS (AutoCompoundingPodLp), and
        // the custodian for the position should have a higher userCollateralBalance
        fl.gt(
            _afterLM.aspTotalSupply,
            _beforeLM.aspTotalSupply,
            "POD-21: Post adding leverage, there should be a higher supply of aspTKNs (AutoCompoundingPodLp)"
        );
    }

    function invariant_POD_22() internal {
        // LeverageManager::addLeverage Post adding leverage, there should be a higher supply of spTKNs (StakingPoolToken) and aspTKNS (AutoCompoundingPodLp), and
        // the custodian for the position should have a higher userCollateralBalance
        fl.gt(
            _afterLM.custodianCollateralBalance,
            _beforeLM.custodianCollateralBalance,
            "POD-22: Post adding leverage, the custodian for the position should have a higher userCollateralBalance"
        );
    }

    function invariant_POD_23() internal {
        // LeverageManager::removeLeverage Post removing leverage, there should be a lower supply of spTKNs (StakingPoolToken) and aspTKNS (AutoCompoundingPodLp), and
        // the custodion for the position should have a lower userCollateralBalance of aspTKNS in FraxLend
        fl.lt(
            _afterLM.spTotalSupply,
            _beforeLM.spTotalSupply,
            "POD-23: Post removing leverage, there should be a lower supply of spTKNs (StakingPoolToken)"
        );
    }

    function invariant_POD_24() internal {
        // LeverageManager::removeLeverage Post removing leverage, there should be a lower supply of spTKNs (StakingPoolToken) and aspTKNS (AutoCompoundingPodLp), and
        // the custodion for the position should have a lower userCollateralBalance of aspTKNS in FraxLend
        fl.lt(
            _afterLM.aspTotalSupply,
            _beforeLM.aspTotalSupply,
            "POD-24: Post removing leverage, there should be a lower supply of aspTKNs (AutoCompoundingPodLp)"
        );
    }

    function invariant_POD_25() internal {
        // LeverageManager::removeLeverage Post removing leverage, there should be a lower supply of spTKNs (StakingPoolToken) and aspTKNS (AutoCompoundingPodLp), and
        // the custodion for the position should have a lower userCollateralBalance of aspTKNS in FraxLend
        fl.lt(
            _afterLM.custodianCollateralBalance,
            _beforeLM.custodianCollateralBalance,
            "POD-25: Post removing leverage, the custodian for the position should have a lower userCollateralBalance"
        );
    }

    function invariant_POD_26(uint256 fraxlendPairSeed) public {
        // FraxLend: cbr change with one large update == cbr change with multiple, smaller updates

        FraxlendPair fraxPair = randomFraxPair(fraxlendPairSeed);

        uint256 thirtyMinTaBefore = _lendingAssetVault.totalAssets();
        vm.warp(block.timestamp + 30 minutes);
        vm.prank(address(fraxPair));
        _lendingAssetVault.whitelistUpdate(true);
        uint256 thirtyMinTaAfter = _lendingAssetVault.totalAssets();

        uint256 tenMinTaBefore = _lendingAssetVault.totalAssets();
        vm.warp(block.timestamp + 10 minutes);
        vm.prank(address(fraxPair));
        _lendingAssetVault.whitelistUpdate(true);

        vm.warp(block.timestamp + 10 minutes);
        vm.prank(address(fraxPair));
        _lendingAssetVault.whitelistUpdate(true);

        vm.warp(block.timestamp + 10 minutes);
        vm.prank(address(fraxPair));
        _lendingAssetVault.whitelistUpdate(true);

        uint256 tenMinTaAfter = _lendingAssetVault.totalAssets();

        fl.eq(
            thirtyMinTaAfter - thirtyMinTaBefore,
            tenMinTaAfter - tenMinTaBefore,
            "POD-26: FraxLend: cbr change with one large update == cbr change with multiple, smaller updates"
        );
    }

    function invariant_POD_27() public {
        // IERC20(pod).balanceOf(leverageManager) == 0, IERC20(pairedLpToken).balanceOf(leverageManager) == 0
        for (uint256 i; i < _pods.length; i++) {
            fl.eq(
                _pods[i].balanceOf(address(_leverageManager)),
                0,
                "POD-27a: LeverageManager contract should never hold any token balances"
            );
            fl.eq(
                IERC20(_pods[i].PAIRED_LP_TOKEN()).balanceOf(address(_leverageManager)),
                0,
                "POD-27b: LeverageManager contract should never hold any token balances"
            );
        }
    }

    function invariant_POD_28() public {
        // FraxlendPair.totalAsset includes both direct deposits and external vault deposits.
        // Therefore, it shouuld always be greater or equal to vaultUtilization mapping tracked in LendingAssetVault
        for (uint256 i; i < _fraxPairs.length; i++) {
            (uint128 pairTotalAssets,) = FraxlendPairCore(address(_fraxPairs[i])).totalAsset();
            fl.gte(
                uint256(pairTotalAssets),
                _lendingAssetVault.vaultUtilization(address(_fraxPairs[i])),
                "POD-28: FraxlendPair.totalAsset should be greater or equal to vaultUtilization (LendingAssetVault)"
            );
        }
    }

    function invariant_POD_29() public {
        // totalAssets must be greater than totalAssetUtilized
        fl.gte(
            _lendingAssetVault.totalAssets(),
            _lendingAssetVault.totalAssetsUtilized(),
            "POD-29: totalAssets must be greater than totalAssetUtilized"
        );
    }

    function invariant_POD_30() internal {
        // repayAsset should not lead to to insolvency
        fl.t(false, "POD-30: repayAsset should not lead to to insolvency");
    }

    function invariant_POD_31() public {
        // staking pool balance should equal token reward shares
        for (uint256 i; i < _pods.length; i++) {
            address stakingToken = _pods[i].lpStakingPool();
            address tokenRewards = StakingPoolToken(stakingToken).POOL_REWARDS();
            for (uint256 user; user < users.length; user++) {
                fl.eq(
                    StakingPoolToken(stakingToken).balanceOf(users[user]),
                    TokenRewards(tokenRewards).shares(users[user]),
                    "POD-31: staking pool balance should equal token reward shares"
                );
            }
        }
    }

    function invariant_POD_32() public {
        // FraxLend: (totalBorrow.amount) / totalAsset.totalAmount(address(externalAssetVault))
        // should never be more than 100%
        for (uint256 i; i < _fraxPairs.length; i++) {
            (uint256 totalAssetAmount,, uint256 totalBorrowAmount,,) = _fraxPairs[i].getPairAccounting();
            fl.lte(
                totalBorrowAmount,
                totalAssetAmount,
                "POD-32: FraxLend: (totalBorrow.amount) / totalAsset.totalAmount(address(externalAssetVault)) should never be more than 100%"
            );
        }
    }

    function invariant_POD_33() public {
        // FraxLend: totalAsset.totalAmount(address(0)) == 0 -> totalBorrow.amount == 0
        for (uint256 i; i < _fraxPairs.length; i++) {
            (uint128 totalAssetAmount,) = FraxlendPairCore(address(_fraxPairs[i])).totalAsset();
            (uint128 totalBorrowAmount,) = FraxlendPairCore(address(_fraxPairs[i])).totalBorrow();
            if (totalAssetAmount == 0) {
                fl.eq(
                    totalBorrowAmount,
                    0,
                    "POD-33: FraxLend: totalAsset.totalAmount(address(0)) == 0 -> totalBorrow.amount == 0"
                );
            }
        }
    }

    function invariant_POD_34(uint256 shares) internal {
        // AutoCompoundingPodLP: mint() should increase asp supply by exactly that amount of shares
        fl.eq(
            _afterASP.aspTotalSupply,
            _beforeASP.aspTotalSupply + shares,
            "POD-34: AutoCompoundingPodLP: mint() should increase asp supply by exactly that amount of shares"
        );
    }

    function invariant_POD_35(uint256 assets) internal {
        // AutoCompoundingPodLP: deposit() should decrease user balance of sp tokens
        // by exact amount of assets passed
        fl.eq(
            _afterASP.spUserBalance,
            _beforeASP.spUserBalance - assets,
            "POD-35: AutoCompoundingPodLP: deposit() should decrease user balance of sp tokens by exact amount of assets passed"
        );
    }

    function invariant_POD_36(uint256 shares) internal {
        // AutoCompoundingPodLP: redeem() should decrease asp supply by exactly that amount of shares
        fl.eq(
            _afterASP.aspTotalSupply,
            _beforeASP.aspTotalSupply - shares,
            "POD-36: AutoCompoundingPodLP: redeem() should decrease asp supply by exactly that amount of shares"
        );
    }

    function invariant_POD_37(uint256 assets) internal {
        // AutoCompoundingPodLP: withdraw() should increase user balance of sp tokens
        // by exact amount of assets passed
        fl.eq(
            _afterASP.spUserBalance,
            _beforeASP.spUserBalance + assets,
            "POD-37: AutoCompoundingPodLP: withdraw() should increase user balance of sp tokens by exact amount of assets passed"
        );
    }

    function invariant_POD_38() internal {
        // AutoCompoundingPodLP: mint/deposit/redeem/withdraw()  spToken total supply should never decrease
        fl.gte(_afterASP.spTotalSupply, _beforeASP.spTotalSupply, "POD-38: spToken totalSupply should never decrease");
    }

    function invariant_POD_39() internal {
        // AutoCompounding should not revert with Insufficient Amount
        fl.t(false, "POD-39: AutoCompounding should not revert with Insufficient Amount");
    }

    function invariant_POD_40() internal {
        // AutoCompounding should not revert with Insufficient Liquidity
        fl.t(false, "POD-40: AutoCompounding should not revert with Insufficient Liquidity");
    }

    function invariant_POD_41() internal {
        // AutoCompoundingPodLP: redeem/withdraw() should never get an InsufficientBalance or underflow/overflow revert
        fl.t(
            false,
            "POD-41: AutoCompoundingPodLP: redeem/withdraw() should never get an InsufficientBalance or underflow/overflow revert"
        );
    }

    function invariant_POD_42(address lendingPair) internal {
        // LeverageManager: custodian position is solvent after adding leverage and removing leverage
        fl.lte(
            _afterLM.custodianLTV,
            FraxlendPair(lendingPair).maxLTV(),
            "POD-42: custodian position is solvent after adding leverage and removing leverage"
        );
    }

    function invariant_POD_43() public {
        // TokenReward: global:  getUnpaid() <= balanceOf reward token
        for (uint256 i; i < _pods.length; i++) {
            address tokenRewards = StakingPoolToken(_pods[i].lpStakingPool()).POOL_REWARDS();
            for (uint256 user; user < users.length; user++) {
                fl.lte(
                    TokenRewards(tokenRewards).getUnpaid(address(_peas), users[user]),
                    _peas.balanceOf(tokenRewards),
                    "POD-43: TokenReward: global:  getUnpaid() <= balanceOf reward token"
                );
            }
        }
    }

    function invariant_POD_44() public {
        // user aspTKN Asset -> aspTKN
        // fl.eq(
        //     _afterASP.userAssetApproval,
        //     0,
        //     "POD-44: LVF: global there should not be any remaining allowances after each function call"
        // );
        // asp Rewards Token -> dexAdapter
        fl.eq(
            _afterASP.aspRewardApproval,
            0,
            "POD-44: LVF: global there should not be any remaining allowances after each function call"
        );
        // asp pod pairedLpToken -> dexAdapter
        fl.eq(
            _afterASP.pairedLpApproval,
            0,
            "POD-44: LVF: global there should not be any remaining allowances after each function call"
        );
        // asp pod -> indexUtils
        fl.eq(
            _afterASP.podIndexUtilsApproval,
            0,
            "POD-44: LVF: global there should not be any remaining allowances after each function call"
        );
        // asp pod pairedLpToken -> indexUtils
        fl.eq(
            _afterASP.pairedLpIndexApproval,
            0,
            "POD-44: LVF: global there should not be any remaining allowances after each function call"
        );
        // leverage manager -> pod LP token -> fraxlend pair
        fl.eq(
            _afterLM.podLpApproval,
            0,
            "POD-44: LVF: global there should not be any remaining allowances after each function call"
        );
        // leverage manager -> pod -> dex adapter
        fl.eq(
            _afterLM.podDexApproval,
            0,
            "POD-44: LVF: global there should not be any remaining allowances after each function call"
        );
        // leverage manager -> pod -> index utils
        fl.eq(
            _afterLM.podIndexApproval,
            0,
            "POD-44: LVF: global there should not be any remaining allowances after each function call"
        );
        // leverage manager -> pod Lp token -> index utils
        fl.eq(
            _afterLM.podLpIndexApproval,
            0,
            "POD-44: LVF: global there should not be any remaining allowances after each function call"
        );
        // fraxlend pair asset -> _lendingAssetVault
        fl.eq(
            _afterLM.pairAssetApproval,
            0,
            "POD-44: LVF: global there should not be any remaining allowances after each function call"
        );
        // leverage manager -> staking pool token -> aspTKN
        fl.eq(
            _afterLM.spTKNApproval,
            0,
            "POD-44: LVF: global there should not be any remaining allowances after each function call"
        );
        // leverage manager -> staking pool token -> index utils
        fl.eq(
            _afterLM.spTKNIndexApproval,
            0,
            "POD-44: LVF: global there should not be any remaining allowances after each function call"
        );
        // custodian -> fraxlend collateral -> fraxlend pair
        fl.eq(
            _afterLM.custodianPairApproval,
            0,
            "POD-44: LVF: global there should not be any remaining allowances after each function call"
        );
    }
}

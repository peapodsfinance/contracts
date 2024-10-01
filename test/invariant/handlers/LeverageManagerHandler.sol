// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Properties} from "../helpers/Properties.sol";

import {FuzzLibString} from "fuzzlib/FuzzLibString.sol";

import {WeightedIndex} from "../../../contracts/WeightedIndex.sol";
import {IDecentralizedIndex} from "../../../contracts/interfaces/IDecentralizedIndex.sol";
import {LeveragePositions} from "../../../contracts/lvf/LeveragePositions.sol";
import {ILeverageManager} from "../../../contracts/interfaces/ILeverageManager.sol";
import {IFlashLoanSource} from "../../../contracts/interfaces/IFlashLoanSource.sol";
import {AutoCompoundingPodLp} from "../../../contracts/AutoCompoundingPodLp.sol";

import {IUniswapV2Pair} from "uniswap-v2/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {FullMath} from "v3-core/libraries/FullMath.sol";
import {Math} from "v2-core/libraries/Math.sol";

import {VaultAccount, VaultAccountingLibrary} from "../modules/fraxlend/libraries/VaultAccount.sol";
import {IFraxlendPair} from "../modules/fraxlend/interfaces/IFraxlendPair.sol";
import {FraxlendPair} from "../modules/fraxlend/FraxlendPair.sol";
import {FraxlendPairCore} from "../modules/fraxlend/FraxlendPairCore.sol";
import {FraxlendPairConstants} from "../modules/fraxlend/FraxlendPairConstants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LeverageManagerHandler is Properties {

    struct InitPositionTemps {
        address user;
        WeightedIndex pod;
    }

    function leverageManager_initializePosition(uint256 userIndexSeed, uint256 podIndexSeed) public {

        // PRE-CONDITIONS
        InitPositionTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.pod = randomPod(podIndexSeed);

        // ACTION
        try _leverageManager.initializePosition(
            address(cache.pod),
            cache.user,
            address(0) // TODO: change when self-lending position is setup
        ) {} catch {
            fl.t(false, "INIT POSITION FAILED");
        }
    }

    struct AddLeverageTemps {
        address user;
        uint256 positionId;
        LeveragePositions positionNFT;
        address podAddress;
        address lendingPair;
        uint256 fraxAssetsAvailable;
        address custodian;
        uint256 pairTotalSupply;
        uint256 liquidityMinted;
        WeightedIndex pod;
        AutoCompoundingPodLp aspTKN;
        address flashSource;
        address flashPaymentToken;
    }

    function leverageManager_addLeverage(uint256 positionIdSeed, uint256 podAmount, uint256 pairedLpAmount) public {

        // PRE-CONDITIONS
        AddLeverageTemps memory cache;
        cache.positionNFT = _leverageManager.positionNFT();
        cache.positionId = fl.clamp(positionIdSeed, 0, cache.positionNFT.totalSupply());
        cache.user = cache.positionNFT.ownerOf(cache.positionId);
        (cache.podAddress, cache.lendingPair, cache.custodian,) = _leverageManager.positionProps(cache.positionId);
        cache.pod = WeightedIndex(payable(cache.podAddress));
        cache.flashSource = _leverageManager.flashSource(cache.podAddress);
        cache.aspTKN = AutoCompoundingPodLp(IFraxlendPair(cache.lendingPair).collateralContract());

        __beforeLM(cache.lendingPair, cache.podAddress, IFraxlendPair(cache.lendingPair).collateralContract(), cache.custodian);

        podAmount = fl.clamp(podAmount, 0, cache.pod.balanceOf(cache.user));
        if (podAmount < 1e14) return;

        address lpPair = _uniV2Factory.getPair(cache.podAddress, cache.pod.PAIRED_LP_TOKEN());
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(lpPair).getReserves();
        pairedLpAmount = _v2SwapRouter.quote(podAmount, reserve0, reserve1);

        vm.prank(cache.user);
        cache.pod.approve(address(_leverageManager), podAmount);
        
        if (pairedLpAmount > IERC20(cache.pod.PAIRED_LP_TOKEN()).balanceOf(IFlashLoanSource(cache.flashSource).source())) return;

        uint256 feeAmount = FullMath.mulDivRoundingUp(pairedLpAmount, 10000, 1e6);

        (uint256 fraxAssets, , uint256 fraxBorrows, , ) = IFraxlendPair(cache.lendingPair).getPairAccounting();
        if (pairedLpAmount + feeAmount > fraxAssets - fraxBorrows) return;

        _updatePrices(positionIdSeed);

        // ACTION
        vm.prank(cache.user);
        try _leverageManager.addLeverage(
            cache.positionId,
            cache.podAddress,
            podAmount,
            pairedLpAmount,
            pairedLpAmount,
            pairedLpAmount + feeAmount,
            1000,
            block.timestamp,
            address(0) // TODO: change when self-lending position is setup
        ) {
            
            // POST-CONDITIONS
            __afterLM(cache.lendingPair, cache.podAddress, IFraxlendPair(cache.lendingPair).collateralContract(), cache.custodian);
            (uint256 fraxAssetsLessVault, ) = FraxlendPair(cache.lendingPair).totalAsset();

            // invariant_POD_4(FraxlendPair(cache.lendingPair));
            // invariant_POD_16();
            // invariant_POD_18();
            invariant_POD_19();
            invariant_POD_21();
            invariant_POD_22();
            invariant_POD_23();
            // invariant_POD_37a();
            invariant_POD_44(cache.lendingPair);

            if (pairedLpAmount + feeAmount > fraxAssetsLessVault - fraxBorrows) {
                invariant_POD_9();
                invariant_POD_10((pairedLpAmount + feeAmount) - (fraxAssetsLessVault - fraxBorrows));
                invariant_POD_11((pairedLpAmount + feeAmount) - (fraxAssetsLessVault - fraxBorrows));
            }
            
        } catch (bytes memory err) {
            bytes4[1] memory errors =
                [FraxlendPairConstants.Insolvent.selector];
            fl.log("ERROR", errors[0]);
            fl.log("SELECTOR", bytes4(err));
            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    fl.log("EXPECTED", expected);
                    break;
                }
            }
            fl.t(expected, FuzzLibString.getRevertMsg(err));
            // return;
        } catch Error(string memory reason) {
            
            string[5] memory stringErrors = [
                "UniswapV2Router: INSUFFICIENT_A_AMOUNT",
                "UniswapV2Router: INSUFFICIENT_B_AMOUNT",
                "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT",
                "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT",
                "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED"
            ];

            bool expected = false;
            for (uint256 i = 0; i < stringErrors.length; i++) {
                if (compareStrings(stringErrors[i], reason)) {
                    expected = true;
                    break;
                }
            }
            fl.t(expected, reason);
        }
    }

    struct RemoveLeverageTemps {
        address user;
        uint256 positionId;
        uint256 interestEarned;
        uint256 repayShares;
        uint256 sharesToBurn;
        LeveragePositions positionNFT;
        address podAddress;
        address lendingPair;
        address borrowToken;
        address custodian;
        address selfLendingPod;
        WeightedIndex pod;
        address flashSource;
    }

    function leverageManager_removeLeverage(
        uint256 positionIdSeed, 
        uint256 borrowAssets, 
        uint256 collateralAmount,
        uint256 userDebtRepay
        ) public {

        // PRE-CONDITIONS
        RemoveLeverageTemps memory cache;
        cache.positionNFT = _leverageManager.positionNFT();
        cache.positionId = fl.clamp(positionIdSeed, 0, cache.positionNFT.totalSupply());
        cache.user = cache.positionNFT.ownerOf(cache.positionId);
        (cache.podAddress, cache.lendingPair, cache.custodian, cache.selfLendingPod) = _leverageManager.positionProps(cache.positionId);

        // I don't think flash is accounting for interest to be added???
        FraxlendPair(cache.lendingPair).addInterest(false);

        __beforeLM(cache.lendingPair, cache.podAddress, IFraxlendPair(cache.lendingPair).collateralContract(), cache.custodian);

        cache.pod = WeightedIndex(payable(cache.podAddress));
        cache.flashSource = _leverageManager.flashSource(cache.podAddress);
        cache.borrowToken = cache.selfLendingPod != address(0) ? 
            IFraxlendPair(cache.lendingPair).asset()
            : IDecentralizedIndex(cache.podAddress).PAIRED_LP_TOKEN();

        (cache.interestEarned, , , , , ) = FraxlendPair(cache.lendingPair).previewAddInterest();

        // borrowAssets starts as shares, will change to assets here in a sec 
        borrowAssets = fl.clamp(borrowAssets, 0, IFraxlendPair(cache.lendingPair).userBorrowShares(cache.custodian));
        cache.repayShares = borrowAssets;
        borrowAssets = VaultAccountingLibrary.toAmount(IFraxlendPair(cache.lendingPair).totalBorrow(), borrowAssets + cache.interestEarned, true);

        cache.sharesToBurn = _lendingAssetVault.vaultUtilization(cache.lendingPair) > borrowAssets ? 
        FraxlendPair(cache.lendingPair).convertToShares(borrowAssets) :
        FraxlendPair(cache.lendingPair).convertToShares(_lendingAssetVault.vaultUtilization(cache.lendingPair));
        
        uint256 feeAmount = FullMath.mulDivRoundingUp(borrowAssets, 10000, 1e6);

        collateralAmount = fl.clamp(collateralAmount, 0, IFraxlendPair(cache.lendingPair).userCollateralBalance(cache.custodian));
        userDebtRepay = fl.clamp(userDebtRepay, 0, IERC20(cache.borrowToken).balanceOf(cache.user));

        if (
            borrowAssets <= 1000 || 
            collateralAmount <= 1000 ||
            cache.sharesToBurn > IERC20(cache.lendingPair).balanceOf(address(_lendingAssetVault)) ||
            borrowAssets > IERC20(IFraxlendPair(cache.lendingPair).asset()).balanceOf(cache.lendingPair)
            ) return;

        if (!_solventCheckAfterRepay(
            cache.custodian,
            cache.lendingPair,
            IFraxlendPair(cache.lendingPair).userBorrowShares(cache.custodian),
            cache.repayShares,
            IFraxlendPair(cache.lendingPair).userCollateralBalance(cache.custodian) - collateralAmount
        )) return;

        vm.prank(cache.user);
        IERC20(cache.borrowToken).approve(address(_leverageManager), borrowAssets+ feeAmount);

        // ACTION
        vm.prank(cache.user);
        try _leverageManager.removeLeverage(
            cache.positionId,
            borrowAssets,
            collateralAmount,
            0,
            0,
            address(_dexAdapter),
            userDebtRepay
        ) {

            // POST-CONDITIONS
            __afterLM(cache.lendingPair, cache.podAddress, IFraxlendPair(cache.lendingPair).collateralContract(), cache.custodian);

            // invariant_POD_4(FraxlendPair(cache.lendingPair));
            // invariant_POD_16();
            invariant_POD_17();
            invariant_POD_20();
            // invariant_POD_24();
            invariant_POD_25();
            invariant_POD_26();
            invariant_POD_44(cache.lendingPair);

            if (_beforeLM.vaultUtilization > 0) {
                invariant_POD_6();
                fl.log("_beforeLM.vaultUtilization", _beforeLM.vaultUtilization);
                fl.log("borrowAssets", borrowAssets);
                // invariant_POD_7(_beforeLM.vaultUtilization > borrowAssets ? borrowAssets : _beforeLM.vaultUtilization);
                // invariant_POD_8(_beforeLM.vaultUtilization > borrowAssets ? borrowAssets : _beforeLM.vaultUtilization);
            }

        } catch Error(string memory reason) {
            
            string[3] memory stringErrors = [
                "UniswapV2Router: INSUFFICIENT_A_AMOUNT",
                "UniswapV2Router: INSUFFICIENT_B_AMOUNT",
                "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT"
            ];

            bool expected = false;
            for (uint256 i = 0; i < stringErrors.length; i++) {
                if (compareStrings(stringErrors[i], reason)) {
                    expected = true;
                    
                } else if (compareStrings(reason, stringErrors[2])) {
                    // invariant_POD_1();
                }
            }
            fl.t(expected, reason);
        }
        // catch (bytes memory err) {

        //     bytes4[1] memory errors = [FraxlendPairConstants.Insolvent.selector]; 

        //     bool expected = false;
        //     for (uint256 i = 0; i < errors.length; i++) {
        //         if (errors[i] == bytes4(err)) {
        //             if (
        //                 IFraxlendPair(cache.lendingPair).userBorrowShares(cache.custodian) != 
        //                 _beforeLM.custodianBorrowShares
        //                 ) {
        //                     invariant_POD_33();
        //                 }
        //         }
        //     }

        // }
    }

    function _solventCheckAfterRepay(
        address borrower,
        address lendingPair,
        uint256 sharesAvailable,
        uint256 repayShares,
        uint256 _collateralAmount
        ) internal returns (bool isSolvent) {
        ( , , , , uint256 highExchangeRate) = FraxlendPair(lendingPair).exchangeRateInfo();

        uint256 sharesAfterRepay = sharesAvailable - repayShares;
        fl.log("SHARES AFTER REPAY", sharesAfterRepay);
        fl.log("sharesAvailable", sharesAvailable);
        fl.log("repayShares", repayShares);
        isSolvent = true;
        uint256 _ltv = (((sharesAfterRepay * highExchangeRate) / FraxlendPair(lendingPair).EXCHANGE_PRECISION()) * FraxlendPair(lendingPair).LTV_PRECISION()) / _collateralAmount;
        isSolvent = _ltv <= FraxlendPair(lendingPair).maxLTV();
    }
}
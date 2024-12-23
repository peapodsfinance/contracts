// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Properties} from "../helpers/Properties.sol";

import {FuzzLibString} from "fuzzlib/FuzzLibString.sol";

import {WeightedIndex} from "../../../contracts/WeightedIndex.sol";
import {IDecentralizedIndex} from "../../../contracts/interfaces/IDecentralizedIndex.sol";
import {LeveragePositions} from "../../../contracts/lvf/LeveragePositions.sol";
import {ILeverageManager} from "../../../contracts/interfaces/ILeverageManager.sol";
import {IFlashLoanSource} from "../../../contracts/interfaces/IFlashLoanSource.sol";
import {AutoCompoundingPodLp} from "../../../contracts/AutoCompoundingPodLp.sol";
import {UniswapV3FlashSource} from "../../../contracts/flash/UniswapV3FlashSource.sol";

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
            address(0), // change for self-lending
            false // change for self-lending
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
        uint256 pairedLpAmount;
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
        (cache.podAddress, cache.lendingPair, cache.custodian,,) = _leverageManager.positionProps(cache.positionId);
        cache.pod = WeightedIndex(payable(cache.podAddress));
        cache.flashSource = _leverageManager.flashSource(IFraxlendPair(cache.lendingPair).asset());
        cache.aspTKN = AutoCompoundingPodLp(IFraxlendPair(cache.lendingPair).collateralContract());

        __beforeLM(
            cache.lendingPair, cache.podAddress, IFraxlendPair(cache.lendingPair).collateralContract(), cache.custodian
        );

        podAmount = fl.clamp(podAmount, 0, cache.pod.balanceOf(cache.user));
        if (podAmount < 1e14) return;

        address lpPair = _uniV2Factory.getPair(cache.podAddress, cache.pod.PAIRED_LP_TOKEN());
        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(lpPair).getReserves();
        cache.pairedLpAmount = _v2SwapRouter.quote(podAmount, reserve0, reserve1);

        vm.prank(cache.user);
        cache.pod.approve(address(_leverageManager), podAmount);

        if (
            cache.pairedLpAmount
                > IERC20(cache.pod.PAIRED_LP_TOKEN()).balanceOf(IFlashLoanSource(cache.flashSource).source())
        ) return;

        uint256 feeAmount = FullMath.mulDivRoundingUp(cache.pairedLpAmount, 10000, 1e6);

        uint256 fraxAssets = FraxlendPair(cache.lendingPair).totalAssets();
        (,, uint256 fraxBorrows,,) = IFraxlendPair(cache.lendingPair).getPairAccounting();
        if (pairedLpAmount + feeAmount > fraxAssets - fraxBorrows) return;

        _updatePrices(positionIdSeed);

        // ACTION
        vm.prank(cache.user);
        try _leverageManager.addLeverage(
            cache.positionId,
            cache.podAddress,
            podAmount,
            cache.pairedLpAmount,
            cache.pairedLpAmount,
            false,
            abi.encode(
                cache.pairedLpAmount + feeAmount, // pairedLpAmount + feeAmount,
                1000,
                block.timestamp
            )
        ) {
            // POST-CONDITIONS
            __afterLM(
                cache.lendingPair,
                cache.podAddress,
                IFraxlendPair(cache.lendingPair).collateralContract(),
                cache.custodian
            );
            (uint256 fraxAssetsLessVault,) = FraxlendPair(cache.lendingPair).totalAsset();
            _afterLM.totalAssetsLAV > _beforeLM.totalAssetsLAV
                ? lavDeposits += _afterLM.totalAssetsLAV - _beforeLM.totalAssetsLAV
                : lavDeposits -= _beforeLM.totalAssetsLAV - _afterLM.totalAssetsLAV;

            invariant_POD_4(FraxlendPair(cache.lendingPair)); // @audit fails
            invariant_POD_17();
            invariant_POD_18();
            invariant_POD_20();
            invariant_POD_21();
            invariant_POD_22();
            invariant_POD_42(cache.lendingPair);

            if (cache.pairedLpAmount + feeAmount > fraxAssetsLessVault - fraxBorrows) {
                invariant_POD_9();
                invariant_POD_10((cache.pairedLpAmount + feeAmount) - (fraxAssetsLessVault - fraxBorrows));
                invariant_POD_11((cache.pairedLpAmount + feeAmount) - (fraxAssetsLessVault - fraxBorrows));
            }
        } catch (bytes memory err) {
            if (getPanicCode(err) == 17 || getPanicCode(err) == 18) return; // @audit added these

            bytes4[1] memory errors = [FraxlendPairConstants.Insolvent.selector];

            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            fl.t(expected, FuzzLibString.getRevertMsg(err));
        } catch Error(string memory reason) {
            string[7] memory stringErrors = [
                "UniswapV2Router: INSUFFICIENT_A_AMOUNT",
                "UniswapV2Router: INSUFFICIENT_B_AMOUNT",
                "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT",
                "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT",
                "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED",
                "SafeERC20: decreased allowance below zero", // @audit added this
                "MS" // @audit added this
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
        bool hasSelfLendingPairPod;
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
        (cache.podAddress, cache.lendingPair, cache.custodian,, cache.hasSelfLendingPairPod) =
            _leverageManager.positionProps(cache.positionId);

        // I don't think flash is accounting for interest to be added???
        FraxlendPair(cache.lendingPair).addInterest(false);

        __beforeLM(
            cache.lendingPair, cache.podAddress, IFraxlendPair(cache.lendingPair).collateralContract(), cache.custodian
        );

        cache.pod = WeightedIndex(payable(cache.podAddress));
        cache.flashSource = _leverageManager.flashSource(IFraxlendPair(cache.lendingPair).asset());
        cache.borrowToken = cache.hasSelfLendingPairPod
            ? IFraxlendPair(cache.lendingPair).asset()
            : IDecentralizedIndex(cache.podAddress).PAIRED_LP_TOKEN();

        (cache.interestEarned,,,,,) = FraxlendPair(cache.lendingPair).previewAddInterest();

        // borrowAssets starts as shares, will change to assets here in a sec
        borrowAssets = fl.clamp(borrowAssets, 0, IFraxlendPair(cache.lendingPair).userBorrowShares(cache.custodian));
        cache.repayShares = borrowAssets;
        borrowAssets = VaultAccountingLibrary.toAmount(
            IFraxlendPair(cache.lendingPair).totalBorrow(), borrowAssets + cache.interestEarned, true
        );

        cache.sharesToBurn = _lendingAssetVault.vaultUtilization(cache.lendingPair) > borrowAssets
            ? FraxlendPair(cache.lendingPair).convertToShares(borrowAssets)
            : FraxlendPair(cache.lendingPair).convertToShares(_lendingAssetVault.vaultUtilization(cache.lendingPair));

        uint256 feeAmount = FullMath.mulDivRoundingUp(borrowAssets, 10000, 1e6);

        collateralAmount =
            fl.clamp(collateralAmount, 0, IFraxlendPair(cache.lendingPair).userCollateralBalance(cache.custodian));
        userDebtRepay = fl.clamp(userDebtRepay, 0, IERC20(cache.borrowToken).balanceOf(cache.user));

        if (
            borrowAssets <= 1000 || collateralAmount <= 1000
                || cache.sharesToBurn > IERC20(cache.lendingPair).balanceOf(address(_lendingAssetVault))
                || borrowAssets > IERC20(IFraxlendPair(cache.lendingPair).asset()).balanceOf(cache.lendingPair)
                || borrowAssets > IERC20(cache.borrowToken).balanceOf(UniswapV3FlashSource(cache.flashSource).source())
        ) return;

        if (
            !_solventCheckAfterRepay(
                cache.custodian,
                cache.lendingPair,
                IFraxlendPair(cache.lendingPair).userBorrowShares(cache.custodian),
                cache.repayShares,
                IFraxlendPair(cache.lendingPair).userCollateralBalance(cache.custodian) - collateralAmount
            )
        ) return;

        vm.prank(cache.user);
        IERC20(cache.borrowToken).approve(address(_leverageManager), borrowAssets + feeAmount);

        // ACTION
        vm.prank(cache.user);
        try _leverageManager.removeLeverage(cache.positionId, borrowAssets, collateralAmount, 0, 0, 0, userDebtRepay) {
            // POST-CONDITIONS
            __afterLM(
                cache.lendingPair,
                cache.podAddress,
                IFraxlendPair(cache.lendingPair).collateralContract(),
                cache.custodian
            );

            _afterLM.totalAssetsLAV > _beforeLM.totalAssetsLAV
                ? lavDeposits += _afterLM.totalAssetsLAV - _beforeLM.totalAssetsLAV
                : lavDeposits -= _beforeLM.totalAssetsLAV - _afterLM.totalAssetsLAV;

            invariant_POD_4(FraxlendPair(cache.lendingPair));
            invariant_POD_16();
            invariant_POD_19();
            invariant_POD_23(); // @audit failing
            invariant_POD_24();
            invariant_POD_25();
            invariant_POD_42(cache.lendingPair);

            if (_beforeLM.vaultUtilization > 0) {
                invariant_POD_6();
                invariant_POD_7(_beforeLM.vaultUtilization > borrowAssets ? borrowAssets : _beforeLM.vaultUtilization); // @audit fails
                invariant_POD_8(_beforeLM.vaultUtilization > borrowAssets ? borrowAssets : _beforeLM.vaultUtilization); // @audit fails
            }
        } catch (bytes memory err) {
            if (getPanicCode(err) == 17) return; // @audit added these
        } catch Error(string memory reason) {
            string[5] memory stringErrors = [
                "UniswapV2Router: INSUFFICIENT_A_AMOUNT",
                "UniswapV2Router: INSUFFICIENT_B_AMOUNT",
                "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT",
                "UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED",
                "SafeERC20: decreased allowance below zero" // @audit added this
            ];

            bool expected = false;
            for (uint256 i = 0; i < stringErrors.length; i++) {
                if (compareStrings(stringErrors[i], reason)) {
                    expected = true;
                } else if (compareStrings(reason, stringErrors[2])) {
                    invariant_POD_1(); // @audit failing
                }
            }
            fl.t(expected, reason);
        }
    }

    function _solventCheckAfterRepay(
        address,
        address lendingPair,
        uint256 sharesAvailable,
        uint256 repayShares,
        uint256 _collateralAmount
    ) internal view returns (bool isSolvent) {
        (,,,, uint256 highExchangeRate) = FraxlendPair(lendingPair).exchangeRateInfo();

        uint256 sharesAfterRepay = sharesAvailable - repayShares;

        isSolvent = true;
        uint256 _ltv = (
            ((sharesAfterRepay * highExchangeRate) / FraxlendPair(lendingPair).EXCHANGE_PRECISION())
                * FraxlendPair(lendingPair).LTV_PRECISION()
        ) / _collateralAmount;
        isSolvent = _ltv <= FraxlendPair(lendingPair).maxLTV();
    }
}

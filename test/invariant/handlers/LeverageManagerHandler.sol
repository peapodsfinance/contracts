// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Properties} from "../helpers/Properties.sol";

import {WeightedIndex} from "../../../contracts/WeightedIndex.sol";
import {IDecentralizedIndex} from "../../../contracts/interfaces/IDecentralizedIndex.sol";
import {LeveragePositions} from "../../../contracts/lvf/LeveragePositions.sol";
import {ILeverageManager} from "../../../contracts/interfaces/ILeverageManager.sol";
import {IFlashLoanSource} from "../../../contracts/interfaces/IFlashLoanSource.sol";

import {IUniswapV2Pair} from "uniswap-v2/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {FullMath} from "v3-core/libraries/FullMath.sol";

import {VaultAccount, VaultAccountingLibrary} from "../modules/fraxlend/libraries/VaultAccount.sol";
import {IFraxlendPair} from "../modules/fraxlend/interfaces/IFraxlendPair.sol";
import {FraxlendPair} from "../modules/fraxlend/FraxlendPair.sol";
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
        address selfLendingPod;
        WeightedIndex pod;
        address flashSource;
        address flashPaymentToken;
    }

    function leverageManager_addLeverage(uint256 positionIdSeed, uint256 podAmount, uint256 pairedLpAmount) public {

        // PRE-CONDITIONS
        AddLeverageTemps memory cache;
        cache.positionNFT = _leverageManager.positionNFT();
        cache.positionId = fl.clamp(positionIdSeed, 0, cache.positionNFT.totalSupply());
        cache.user = cache.positionNFT.ownerOf(cache.positionId);
        (cache.podAddress, cache.lendingPair, cache.custodian, cache.selfLendingPod) = _leverageManager.positionProps(cache.positionId);
        cache.pod = WeightedIndex(payable(cache.podAddress));
        cache.flashSource = _leverageManager.flashSource(cache.podAddress);

        podAmount = fl.clamp(podAmount, 0, cache.pod.balanceOf(cache.user));
        if (podAmount < 1e14) return;

        address lpPair = _uniV2Factory.getPair(cache.podAddress, cache.pod.PAIRED_LP_TOKEN());
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(lpPair).getReserves();
        pairedLpAmount = _v2SwapRouter.quote(podAmount, reserve0, reserve1);

        vm.prank(cache.user);
        cache.pod.approve(address(_leverageManager), podAmount);
        
        if (pairedLpAmount > IERC20(cache.pod.PAIRED_LP_TOKEN()).balanceOf(IFlashLoanSource(cache.flashSource).source())) return;

        uint256 feeAmount = FullMath.mulDivRoundingUp(pairedLpAmount, 10000, 1e6);
        // IERC20(cache.pod.PAIRED_LP_TOKEN()).transfer(address(_leverageManager), feeAmount);

        (uint256 fraxAssets, , uint256 fraxBorrows, , ) = IFraxlendPair(cache.lendingPair).getPairAccounting();
        if (pairedLpAmount + feeAmount > fraxAssets - fraxBorrows) return;

        _peasPriceFeed.updateAnswer(3e18);
        _daiPriceFeed.updateAnswer(1e18);
        _wethPriceFeed.updateAnswer(3000e18);

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
            uint256 sharesReturned = IFraxlendPair(cache.lendingPair).userBorrowShares(cache.custodian);
            uint256 _borrowAssetssToRepay = VaultAccountingLibrary.toAmount(IFraxlendPair(cache.lendingPair).totalBorrow(), sharesReturned, false);
            fl.log(
                "USER ASSET BALANCE", 
                _borrowAssetssToRepay
            );
        } catch {
            fl.t(false, "ADD LEVERAGE FAILED");
        }
    }

    struct RemoveLeverageTemps {
        address user;
        uint256 positionId;
        uint256 interestEarned;
        uint256 repayShares;
        LeveragePositions positionNFT;
        address podAddress;
        address lendingPair;
        address borrowToken;
        address custodian;
        address selfLendingPod;
        WeightedIndex pod;
        address flashSource;
    }

    function leverageManager_removeLeverage(uint256 positionIdSeed, uint256 borrowAssets, uint256 collateralAmount) public {

        // PRE-CONDITIONS
        RemoveLeverageTemps memory cache;
        cache.positionNFT = _leverageManager.positionNFT();
        cache.positionId = fl.clamp(positionIdSeed, 0, cache.positionNFT.totalSupply());
        cache.user = cache.positionNFT.ownerOf(cache.positionId);
        (cache.podAddress, cache.lendingPair, cache.custodian, cache.selfLendingPod) = _leverageManager.positionProps(cache.positionId);

        // I don't think flash is accounting for interest to be added???
        FraxlendPair(cache.lendingPair).addInterest(false);

        cache.pod = WeightedIndex(payable(cache.podAddress));
        cache.flashSource = _leverageManager.flashSource(cache.podAddress);
        cache.borrowToken = cache.selfLendingPod != address(0) ? 
            IFraxlendPair(cache.lendingPair).asset()
            : IDecentralizedIndex(cache.podAddress).PAIRED_LP_TOKEN();

        address lpPair = _uniV2Factory.getPair(cache.podAddress, cache.pod.PAIRED_LP_TOKEN());
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(lpPair).getReserves();

        (cache.interestEarned, , , , , ) = FraxlendPair(cache.lendingPair).previewAddInterest();

        // borrowAssets starts as shares, will change to assets here in a sec 
        borrowAssets = fl.clamp(borrowAssets, 0, IFraxlendPair(cache.lendingPair).userBorrowShares(cache.custodian));
        cache.repayShares = borrowAssets;
        borrowAssets = VaultAccountingLibrary.toAmount(IFraxlendPair(cache.lendingPair).totalBorrow(), borrowAssets + cache.interestEarned, false);
        fl.log("BORROWASSETS", borrowAssets);
        uint256 feeAmount = FullMath.mulDivRoundingUp(borrowAssets, 10000, 1e6);

        collateralAmount = fl.clamp(collateralAmount, 0, IFraxlendPair(cache.lendingPair).userCollateralBalance(cache.custodian));

        if (borrowAssets == 0 || borrowAssets > reserve0 || collateralAmount <= 1000) return;

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
            borrowAssets + feeAmount
        ) {} catch {
            fl.t(false, "ADD LEVERAGE FAILED");
        }
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
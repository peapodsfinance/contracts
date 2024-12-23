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

import {IUniswapV2Pair} from "uniswap-v2/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {FullMath} from "v3-core/libraries/FullMath.sol";
import {Math} from "v2-core/libraries/Math.sol";

import {VaultAccount, VaultAccountingLibrary} from "../modules/fraxlend/libraries/VaultAccount.sol";
import {IFraxlendPair} from "../modules/fraxlend/interfaces/IFraxlendPair.sol";
import {FraxlendPair} from "../modules/fraxlend/FraxlendPair.sol";
import {FraxlendPairCore} from "../modules/fraxlend/FraxlendPairCore.sol";
import {FraxlendPairConstants} from "../modules/fraxlend/FraxlendPairConstants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FraxlendPairHandler is Properties {
    // deposit
    struct FraxDepositTemps {
        address user;
        address receiver;
        address fraxAsset;
        FraxlendPair fraxPair;
    }

    function fraxPair_deposit(uint256 userIndexSeed, uint256 receiverIndexSeed, uint256 fraxlendSeed, uint256 amount)
        public
    {
        // PRE-CONDITIONS
        FraxDepositTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.fraxPair = randomFraxPair(fraxlendSeed);
        cache.fraxAsset = cache.fraxPair.asset();

        amount = fl.clamp(amount, 0, IERC20(cache.fraxAsset).balanceOf(cache.user));

        vm.prank(cache.user);
        IERC20(cache.fraxAsset).approve(address(cache.fraxPair), amount);

        // ACTION
        vm.prank(cache.user);
        try cache.fraxPair.deposit(amount, cache.receiver) {}
        catch {
            fl.t(false, "FRAX DEPOSIT FAILED");
        }
    }

    // mint
    struct FraxMintTemps {
        address user;
        address receiver;
        address fraxAsset;
        uint256 assets;
        FraxlendPair fraxPair;
    }

    function fraxPair_mint(uint256 userIndexSeed, uint256 receiverIndexSeed, uint256 fraxlendSeed, uint256 shares)
        public
    {
        // PRE-CONDITIONS
        FraxMintTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.fraxPair = randomFraxPair(fraxlendSeed);
        cache.fraxAsset = cache.fraxPair.asset();

        shares = fl.clamp(shares, 0, cache.fraxPair.convertToShares(IERC20(cache.fraxAsset).balanceOf(cache.user)));
        cache.assets = cache.fraxPair.toAssetAmount(shares, true, true);

        vm.prank(cache.user);
        IERC20(cache.fraxAsset).approve(address(cache.fraxPair), cache.assets);

        // ACTION
        vm.prank(cache.user);
        try cache.fraxPair.mint(shares, cache.receiver) {}
        catch {
            fl.t(false, "FRAX MINT FAILED");
        }
    }
    // redeem

    struct FraxRedeemTemps {
        address user;
        address receiver;
        address fraxAsset;
        uint256 assets;
        uint256 fraxAssets;
        uint256 fraxBorrows;
        FraxlendPair fraxPair;
    }

    function fraxPair_redeem(uint256 userIndexSeed, uint256 receiverIndexSeed, uint256 fraxlendSeed, uint256 shares)
        public
    {
        // PRE-CONDITIONS
        FraxRedeemTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.fraxPair = randomFraxPair(fraxlendSeed);
        cache.fraxAsset = cache.fraxPair.asset();

        shares = fl.clamp(shares, 0, IERC20(cache.fraxPair).balanceOf(cache.user));
        cache.assets = cache.fraxPair.convertToAssets(shares);

        (cache.fraxAssets,, cache.fraxBorrows,,) = cache.fraxPair.getPairAccounting();
        if (cache.assets > cache.fraxAssets - cache.fraxBorrows) return;

        // ACTION
        vm.prank(cache.user);
        try cache.fraxPair.redeem(shares, cache.receiver, cache.user) {}
        catch {
            fl.t(false, "FRAX REDEEM FAILED");
        }
    }

    // withdraw
    struct FraxWithdrawTemps {
        address user;
        address receiver;
        address fraxAsset;
        uint256 fraxAssets;
        uint256 fraxBorrows;
        FraxlendPair fraxPair;
    }

    function fraxPair_withdraw(uint256 userIndexSeed, uint256 receiverIndexSeed, uint256 fraxlendSeed, uint256 amount)
        public
    {
        // PRE-CONDITIONS
        FraxWithdrawTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.fraxPair = randomFraxPair(fraxlendSeed);
        cache.fraxAsset = cache.fraxPair.asset();

        amount = fl.clamp(amount, 0, cache.fraxPair.convertToAssets(IERC20(cache.fraxPair).balanceOf(cache.user)));

        (cache.fraxAssets,, cache.fraxBorrows,,) = cache.fraxPair.getPairAccounting();
        if (amount > cache.fraxAssets - cache.fraxBorrows) return;

        // ACTION
        vm.prank(cache.user);
        try cache.fraxPair.withdraw(amount, cache.receiver, cache.user) {}
        catch {
            fl.t(false, "FRAX WITHDRAW FAILED");
        }
    }

    // borrowAsset
    struct FraxBorrowTemps {
        address user;
        address receiver;
        address fraxAsset;
        address pod;
        IERC20 fraxCollateral;
        uint256 fraxAssets;
        uint256 fraxBorrows;
        uint256 borrowCapacity;
        FraxlendPair fraxPair;
    }

    function fraxPair_borrowAsset(
        uint256 userIndexSeed,
        uint256 receiverIndexSeed,
        uint256 fraxlendSeed,
        uint256 borrowAmount,
        uint256 collateralAmount
    ) public {
        // PRE-CONDITIONS
        FraxBorrowTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.pod = address(randomPod(fraxlendSeed));
        cache.fraxPair = randomFraxPair(fraxlendSeed);
        cache.fraxAsset = cache.fraxPair.asset();
        cache.fraxCollateral = cache.fraxPair.collateralContract();
        (cache.fraxAssets,, cache.fraxBorrows,,) = cache.fraxPair.getPairAccounting();

        __beforeFrax(address(cache.fraxPair), cache.user);
        __beforeLM(address(cache.fraxPair), cache.pod, address(cache.fraxCollateral), address(0));

        cache.borrowCapacity = cache.fraxPair.borrowLimit() - cache.fraxBorrows;
        borrowAmount = fl.clamp(borrowAmount, 0, cache.borrowCapacity);

        if (borrowAmount > cache.fraxAssets - cache.fraxBorrows) return;

        collateralAmount = fl.clamp(collateralAmount, 0, cache.fraxCollateral.balanceOf(cache.user));

        vm.prank(cache.user);
        cache.fraxCollateral.approve(address(cache.fraxPair), collateralAmount);

        _updatePrices(userIndexSeed);

        // ACTION
        vm.prank(cache.user);
        cache.fraxPair.borrowAsset(borrowAmount, collateralAmount, cache.receiver);

        // POST-CONDITIONS
        __afterFrax(address(cache.fraxPair), cache.user);
        __afterLM(address(cache.fraxPair), cache.pod, address(cache.fraxCollateral), address(0));
        _afterLM.totalAssetsLAV > _beforeLM.totalAssetsLAV
            ? lavDeposits += _afterLM.totalAssetsLAV - _beforeLM.totalAssetsLAV
            : lavDeposits -= _beforeLM.totalAssetsLAV - _afterLM.totalAssetsLAV;

        invariant_POD_4(cache.fraxPair);
    }

    // addCollateral
    struct AddCollateralTemps {
        address user;
        address borrower;
        IERC20 fraxCollateral;
        FraxlendPair fraxPair;
    }

    function fraxPair_addCollateral(
        uint256 userIndexSeed,
        uint256 borrowerIndexSeed,
        uint256 fraxlendSeed,
        uint256 collateralAmount
    ) public {
        // PRE-CONDITIONS
        AddCollateralTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.borrower = randomAddress(borrowerIndexSeed);
        cache.fraxPair = randomFraxPair(fraxlendSeed);
        cache.fraxCollateral = cache.fraxPair.collateralContract();

        collateralAmount = fl.clamp(collateralAmount, 0, cache.fraxCollateral.balanceOf(cache.user));

        vm.prank(cache.user);
        cache.fraxCollateral.approve(address(cache.fraxPair), collateralAmount);

        // ACTION
        vm.prank(cache.user);
        // try
        cache.fraxPair.addCollateral(collateralAmount, cache.borrower);
        //  {} catch {
        //     fl.t(false, "ADD COLLATERAL FAILED");
        // }
    }

    // removeCollateral
    struct RemoveCollateralTemps {
        address user;
        address receiver;
        IERC20 fraxCollateral;
        FraxlendPair fraxPair;
    }

    function fraxPair_removeCollateral(
        uint256 userIndexSeed,
        uint256 receiverIndexSeed,
        uint256 fraxlendSeed,
        uint256 collateralAmount
    ) public {
        // PRE-CONDITIONS
        RemoveCollateralTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.fraxPair = randomFraxPair(fraxlendSeed);
        cache.fraxCollateral = cache.fraxPair.collateralContract();

        collateralAmount = fl.clamp(collateralAmount, 0, cache.fraxPair.userCollateralBalance(cache.user));

        _updatePrices(userIndexSeed);

        // ACTION
        vm.prank(cache.user);
        // try
        cache.fraxPair.removeCollateral(collateralAmount, cache.receiver);
        //  {} catch (bytes memory err) {
        //     bytes4[1] memory errors =
        //         [FraxlendPairConstants.Insolvent.selector];
        //     bool expected = false;
        //     for (uint256 i = 0; i < errors.length; i++) {
        //         if (errors[i] == bytes4(err)) {
        //             expected = true;
        //             break;
        //         }
        //     }
        //     fl.t(expected, FuzzLibString.getRevertMsg(err));
        // }
    }

    // repayAsset
    struct RepayAssetTemps {
        address user;
        address borrower;
        address pod;
        uint256 amountToRepay;
        uint256 sharesToBurn;
        IERC20 fraxCollateral;
        IERC20 fraxAsset;
        FraxlendPair fraxPair;
    }

    function fraxPair_repayAsset(uint256 userIndexSeed, uint256 borrowerIndexSeed, uint256 fraxlendSeed, uint256 shares)
        public
    {
        // PRE-CONDITIONS
        RepayAssetTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.borrower = randomAddress(borrowerIndexSeed);
        cache.pod = address(randomPod(fraxlendSeed));
        cache.fraxPair = randomFraxPair(fraxlendSeed);
        cache.fraxCollateral = cache.fraxPair.collateralContract();
        cache.fraxAsset = IERC20(cache.fraxPair.asset());

        __beforeLM(address(cache.fraxPair), cache.pod, address(cache.fraxCollateral), address(0));

        shares = fl.clamp(shares, 0, cache.fraxPair.userBorrowShares(cache.borrower));
        cache.amountToRepay = cache.fraxPair.toBorrowAmount(shares, true, true);

        cache.sharesToBurn = _lendingAssetVault.vaultUtilization(address(cache.fraxPair)) > cache.amountToRepay
            ? cache.fraxPair.convertToShares(cache.amountToRepay)
            : cache.fraxPair.convertToShares(_lendingAssetVault.vaultUtilization(address(cache.fraxPair)));

        if (
            cache.amountToRepay > cache.fraxAsset.balanceOf(cache.user)
                || cache.sharesToBurn > cache.fraxPair.balanceOf(address(_lendingAssetVault))
        ) return;

        vm.prank(cache.user);
        cache.fraxAsset.approve(address(cache.fraxPair), cache.amountToRepay);

        // ACTION
        vm.prank(cache.user);
        try cache.fraxPair.repayAsset(shares, cache.borrower) {
            // POST-CONDITIONS
            __afterLM(address(cache.fraxPair), cache.pod, address(cache.fraxCollateral), address(0));
            _afterLM.totalAssetsLAV > _beforeLM.totalAssetsLAV
                ? lavDeposits += _afterLM.totalAssetsLAV - _beforeLM.totalAssetsLAV
                : lavDeposits -= _beforeLM.totalAssetsLAV - _afterLM.totalAssetsLAV;

            invariant_POD_4(cache.fraxPair);
        } catch (bytes memory err) {
            bytes4[1] memory errors = [FraxlendPairConstants.Insolvent.selector];
            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    invariant_POD_30();
                }
            }
            fl.t(expected, FuzzLibString.getRevertMsg(err));
        }
    }

    // liquidate
    struct LiquidateTemps {
        address user;
        uint256 positionId;
        LeveragePositions positionNFT;
        address podAddress;
        address lendingPair;
        uint256 fraxAssetsAvailable;
        address custodian;
        address fraxAsset;
        uint256 fraxAssets;
        uint256 fraxBorrows;
        FraxlendPair fraxPair;
    }

    function fraxPair_liquidate(uint256 positionIdSeed, uint128 shares) public {
        // PRE-CONDITIONS
        LiquidateTemps memory cache;
        cache.positionNFT = _leverageManager.positionNFT();
        cache.positionId = fl.clamp(positionIdSeed, 0, cache.positionNFT.totalSupply());
        cache.user = cache.positionNFT.ownerOf(cache.positionId);
        (cache.podAddress, cache.lendingPair, cache.custodian,,) = _leverageManager.positionProps(cache.positionId);
        cache.fraxPair = FraxlendPair(cache.lendingPair);

        __beforeLM(
            cache.lendingPair, cache.podAddress, IFraxlendPair(cache.lendingPair).collateralContract(), cache.custodian
        );

        shares = uint128(fl.clamp(uint256(shares), 0, cache.fraxPair.userBorrowShares(cache.custodian)));
        if (shares == 0) return;
        _updatePrices(positionIdSeed);

        // ACTION
        try cache.fraxPair.liquidate(shares, block.timestamp, cache.custodian) {
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
        } catch (bytes memory err) {
            bytes4[1] memory errors = [FraxlendPairConstants.BorrowerSolvent.selector];
            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == bytes4(err)) {
                    expected = true;
                    break;
                }
            }
            fl.t(expected, FuzzLibString.getRevertMsg(err));
        }
    }
    // leveragedPosition
    // struct LeveragedPositionTemps {

    // }

    // function fraxPair_leveragedPosition() public {

    //     // PRE-CONDITIONS

    //     // ACTION
    // }
    // repayAssetWithCollateral
}

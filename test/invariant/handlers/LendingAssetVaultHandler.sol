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

contract LendingAssetVaultHandler is Properties {

    struct LavDepositTemps {
        address user;
        address receiver;
        address vaultAsset;
    }

    function lendingAssetVault_deposit(
        uint256 userIndexSeed,
        uint256 receiverIndexSeed,
        uint256 amount
    ) public {

        // PRE-CONDITIONS
        LavDepositTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.vaultAsset = _lendingAssetVault.asset();

        __beforeLav(cache.user, cache.receiver);

        amount = fl.clamp(amount, 0, IERC20(cache.vaultAsset).balanceOf(cache.user));

        vm.prank(cache.user);
        IERC20(cache.vaultAsset).approve(address(_lendingAssetVault), amount);
        // ACTION
        vm.prank(cache.user);
        try _lendingAssetVault.deposit(
            amount,
            cache.receiver
        ) returns (uint256 sharesMinted) {

            // POST-CONDITIONS
            __afterLav(cache.user, cache.receiver);

            invariant_POD_2(sharesMinted);

            lavDeposits += amount;
            fl.log("LAV DEPOSITS", lavDeposits);

        } catch {
            fl.t(false, "LAV DEPOSIT FAILED");
        }
    }

    struct LavMintTemps {
        address user;
        address receiver;
        address vaultAsset;
        uint256 assets;
        uint256 sharesMinted;
    }

    function lendingAssetVault_mint(
        uint256 userIndexSeed,
        uint256 receiverIndexSeed,
        uint256 shares
    ) public {

        // PRE-CONDITIONS
        LavMintTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.vaultAsset = _lendingAssetVault.asset();

        __beforeLav(cache.user, cache.receiver);

        shares = fl.clamp(shares, 0, _lendingAssetVault.convertToShares(IERC20(cache.vaultAsset).balanceOf(cache.user)));
        cache.assets = _lendingAssetVault.convertToAssets(shares);

        vm.prank(cache.user);
        IERC20(cache.vaultAsset).approve(address(_lendingAssetVault), cache.assets);

        // ACTION
        vm.prank(cache.user);
        try _lendingAssetVault.mint(
            shares,
            cache.receiver
        ) returns (uint256 assetsMinted) {

            // POST-CONDITIONS
            __afterLav(cache.user, cache.receiver);

            cache.sharesMinted = _lendingAssetVault.convertToShares(assetsMinted);
            fl.log("Doanted amount", donatedAmount);
            fl.log("Doanted amount shares", _lendingAssetVault.convertToShares(donatedAmount));
            invariant_POD_2(cache.sharesMinted);

            lavDeposits += assetsMinted;
            fl.log("LAV DEPOSITS", lavDeposits);

        } catch {
            fl.t(false, "LAV MINT FAILED");
        }
    }

    struct LavWithdrawTemps {
        address user;
        address receiver;
        address vaultAsset;
        uint256 assets;
    }

    function lendingAssetVault_withdraw(
        uint256 userIndexSeed,
        uint256 receiverIndexSeed,
        uint256 assets
    ) public {

        // PRE-CONDITIONS
        LavMintTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.vaultAsset = _lendingAssetVault.asset();

        __beforeLav(cache.user, cache.receiver);

        assets = fl.clamp(assets, 0, _lendingAssetVault.maxWithdraw(cache.user));

        if (assets > _lendingAssetVault.totalAvailableAssets()) return;

        // ACTION
        vm.prank(cache.user);
        try _lendingAssetVault.withdraw(
            assets,
            cache.receiver,
            address(0)
        ) returns (uint256 sharesWithdrawn) {

            // POST-CONDITIONS
            __afterLav(cache.user, cache.receiver);

            invariant_POD_3(sharesWithdrawn);

            lavDeposits -= assets;
            fl.log("LAV DEPOSITS", lavDeposits);

        } catch {
            fl.t(false, "LAV WITHDRAW FAILED");
        }
    }

    struct LavRedeemTemps {
        address user;
        address receiver;
        address vaultAsset;
        uint256 assets;
    }

    function lendingAssetVault_redeem(
        uint256 userIndexSeed,
        uint256 receiverIndexSeed,
        uint256 shares
    ) public {

        // PRE-CONDITIONS
        LavMintTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.vaultAsset = _lendingAssetVault.asset();

        __beforeLav(cache.user, cache.receiver);

        shares = fl.clamp(shares, 0, _lendingAssetVault.maxRedeem(cache.user));
        cache.assets = _lendingAssetVault.convertToAssets(shares);

        if (cache.assets > _lendingAssetVault.totalAvailableAssets()) return;
        
        // ACTION
        vm.prank(cache.user);
        try _lendingAssetVault.redeem(
            shares,
            cache.receiver,
            address(0)
        ) returns (uint256 assetsWithdrawn) {

            // POST-CONDITIONS
            __afterLav(cache.user, cache.receiver);

            invariant_POD_3(shares);

            lavDeposits -= assetsWithdrawn;
            fl.log("LAV DEPOSITS", lavDeposits);

        } catch {
            fl.t(false, "LAV REDEEM FAILED");
        }
    }

    struct DonateTemps {
        address user;
        address vaultAsset;
        uint256 interestEarned;
    }

    function lendingAssetVault_donate(
        uint256 userIndexSeed,
        uint256 amount
    ) public {

        // PRE-CONDITIONS
        DonateTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.vaultAsset = _lendingAssetVault.asset();

        __beforeLav(cache.user, address(0));

        amount = fl.clamp(amount, 0, IERC20(cache.vaultAsset).balanceOf(cache.user));

        vm.prank(cache.user);
        IERC20(cache.vaultAsset).approve(address(_lendingAssetVault), amount);

        // ACTION
        vm.prank(cache.user);
        try _lendingAssetVault.donate(amount) {
            donatedAmount += amount;
            lavDeposits += amount;
            
            // POST-CONDITIONS
            __afterLav(cache.user, address(0));

            if (amount != 0) invariant_POD_14(amount);
            
        } catch {
            fl.t(false, "DONATE FAILED");
        }
    }

    struct LavRedeemVaultTemps {
        address user;
        address lendingPairAsset;
        uint256 assetShares;
        uint256 assets;
        FraxlendPair lendingPair;
    }

    function lendingAssetVault_redeemFromVault(
        uint256 userIndexSeed,
        uint256 lendingPairSeed,
        uint256 shares
    ) public {

        // PRE-CONDITIONS
        LavRedeemVaultTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.lendingPair = randomFraxPair(lendingPairSeed);
        cache.lendingPairAsset = cache.lendingPair.asset();
        (cache.assetShares, , ) = cache.lendingPair.getUserSnapshot(address(_lendingAssetVault));

        shares = fl.clamp(shares, 0, cache.assetShares);
        cache.assets = shares == 0 ? cache.lendingPair.convertToAssets(cache.lendingPair.balanceOf(address(_lendingAssetVault))) : cache.lendingPair.convertToAssets(shares);
        
        if (
            cache.assets > IERC20(cache.lendingPairAsset).balanceOf(address(cache.lendingPair))
            ) return;
        
        // ACTION
        vm.prank(cache.user);
        try _lendingAssetVault.redeemFromVault(address(cache.lendingPair), shares) {} catch Panic(uint256 errorCode) {
            uint256[1] memory errors = [
                uint256(17)
            ];

            bool expected = false;
            for (uint256 i = 0; i < errors.length; i++) {
                if (errors[i] == errorCode) {
                    expected = true;
                }
                fl.t(
                    expected,
                    "REDEEM FAILED"
                );
            }
        }
    }
}
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

        amount = fl.clamp(amount, 0, IERC20(cache.vaultAsset).balanceOf(cache.user));

        vm.prank(cache.user);
        IERC20(cache.vaultAsset).approve(address(_lendingAssetVault), amount);
        // ACTION
        vm.prank(cache.user);
        try _lendingAssetVault.deposit(
            amount,
            cache.receiver
        ) {} catch {
            fl.t(false, "LAV DEPOSIT FAILED");
        }
    }

    struct LavMintTemps {
        address user;
        address receiver;
        address vaultAsset;
        uint256 assets;
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

        shares = fl.clamp(shares, 0, _lendingAssetVault.convertToShares(IERC20(cache.vaultAsset).balanceOf(cache.user)));
        cache.assets = _lendingAssetVault.convertToAssets(shares);

        vm.prank(cache.user);
        IERC20(cache.vaultAsset).approve(address(_lendingAssetVault), cache.assets);

        // ACTION
        vm.prank(cache.user);
        try _lendingAssetVault.mint(
            shares,
            cache.receiver
        ) {} catch {
            fl.t(false, "LAV DEPOSIT FAILED");
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

        assets = fl.clamp(assets, 0, _lendingAssetVault.maxWithdraw(cache.user));

        // ACTION
        vm.prank(cache.user);
        try _lendingAssetVault.withdraw(
            assets,
            cache.receiver,
            address(0)
        ) {} catch {
            fl.t(false, "LAV DEPOSIT FAILED");
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
        cache.assets = shares == 0 ? cache.lendingPair.balanceOf(address(this)) : cache.lendingPair.convertToAssets(shares);

        (uint256 fraxAssets, , uint256 fraxBorrows, , ) = cache.lendingPair.getPairAccounting();

        if (
            cache.assets > IERC20(cache.lendingPairAsset).balanceOf(address(cache.lendingPair)) ||
            cache.assets > fraxAssets - fraxBorrows || 
            _lendingAssetVault.vaultUtilization(address(cache.lendingPair)) == 0
            ) return;

        // ACTION
        vm.prank(cache.user);
        try _lendingAssetVault.redeemFromVault(address(cache.lendingPair), shares) {} catch {
            fl.t(false, "LAV REDEEM FAILED");
        }
    }
}
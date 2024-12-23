// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Properties} from "../helpers/Properties.sol";

import {WeightedIndex} from "../../../contracts/WeightedIndex.sol";
import {IDecentralizedIndex} from "../../../contracts/interfaces/IDecentralizedIndex.sol";
import {LeveragePositions} from "../../../contracts/lvf/LeveragePositions.sol";
import {ILeverageManager} from "../../../contracts/interfaces/ILeverageManager.sol";
import {IFlashLoanSource} from "../../../contracts/interfaces/IFlashLoanSource.sol";
import {AutoCompoundingPodLp} from "../../../contracts/AutoCompoundingPodLp.sol";
import {StakingPoolToken} from "../../../contracts/StakingPoolToken.sol";

import {IUniswapV2Pair} from "uniswap-v2/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {FullMath} from "v3-core/libraries/FullMath.sol";

import {VaultAccount, VaultAccountingLibrary} from "../modules/fraxlend/libraries/VaultAccount.sol";
import {IFraxlendPair} from "../modules/fraxlend/interfaces/IFraxlendPair.sol";
import {FraxlendPair} from "../modules/fraxlend/FraxlendPair.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AutoCompoundingPodLpHandler is Properties {
    struct DepositTemps {
        address user;
        address receiver;
        address aspTKNAsset;
        address aspTKNAddress;
        StakingPoolToken spTKN;
        AutoCompoundingPodLp aspTKN;
    }

    function aspTKN_deposit(uint256 userIndexSeed, uint256 receiverIndexSeed, uint256 aspTKNSeed, uint256 assets)
        public
    {
        // PRE-CONDITIONS
        DepositTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.aspTKN = randomAspTKN(aspTKNSeed);
        cache.aspTKNAddress = address(cache.aspTKN);
        cache.aspTKNAsset = cache.aspTKN.asset();
        cache.spTKN = StakingPoolToken(IDecentralizedIndex(cache.aspTKN.pod()).lpStakingPool());

        assets = fl.clamp(assets, 0, IERC20(cache.aspTKNAsset).balanceOf(cache.user));
        if (assets == 0 || cache.aspTKN.convertToShares(assets) == 0) return;

        __beforeAsp(cache.aspTKN, cache.spTKN, cache.user, cache.receiver);

        vm.prank(cache.user);
        IERC20(cache.aspTKNAsset).approve(cache.aspTKNAddress, assets);

        // ACTION
        vm.prank(cache.user);
        try cache.aspTKN.deposit(assets, cache.receiver) {
            // POST-CONDITIONS
            __afterAsp(cache.aspTKN, cache.spTKN, cache.user, cache.receiver);

            invariant_POD_35(assets);
            invariant_POD_38();
        } catch Error(string memory reason) {
            string[8] memory stringErrors = [
                "UniswapV2Router: INSUFFICIENT_A_AMOUNT",
                "UniswapV2Router: INSUFFICIENT_B_AMOUNT",
                "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT",
                "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT",
                "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED",
                "ERC20: transfer amount exceeds balance",
                "MS",
                "SafeERC20: decreased allowance below zero" // @audit added this
            ];

            bool expected = false;
            for (uint256 i = 0; i < stringErrors.length; i++) {
                if (compareStrings(stringErrors[i], reason)) {
                    expected = true;
                }
            }
            if (
                compareStrings(reason, stringErrors[0]) || compareStrings(reason, stringErrors[1])
                    || compareStrings(reason, stringErrors[2]) || compareStrings(reason, stringErrors[3])
            ) {
                invariant_POD_39();
            } else if (compareStrings(reason, stringErrors[4])) {
                invariant_POD_40();
            }
            fl.t(expected, reason);
        }
    }

    struct MintTemps {
        address user;
        address receiver;
        address aspTKNAsset;
        address aspTKNAddress;
        uint256 assets;
        StakingPoolToken spTKN;
        AutoCompoundingPodLp aspTKN;
    }

    function aspTKN_mint(uint256 userIndexSeed, uint256 receiverIndexSeed, uint256 aspTKNSeed, uint256 shares) public {
        // PRE-CONDITIONS
        MintTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.aspTKN = randomAspTKN(aspTKNSeed);
        cache.aspTKNAddress = address(cache.aspTKN);
        cache.aspTKNAsset = cache.aspTKN.asset();
        cache.spTKN = StakingPoolToken(IDecentralizedIndex(cache.aspTKN.pod()).lpStakingPool());

        shares = fl.clamp(shares, 0, cache.aspTKN.convertToShares(IERC20(cache.aspTKNAsset).balanceOf(cache.user)));
        if (shares == 0) return;

        cache.assets = cache.aspTKN.convertToAssets(shares);

        __beforeAsp(cache.aspTKN, cache.spTKN, cache.user, cache.receiver);

        vm.prank(cache.user);
        IERC20(cache.aspTKNAsset).approve(cache.aspTKNAddress, type(uint256).max);

        // ACTION
        vm.prank(cache.user);
        try cache.aspTKN.mint(shares, cache.receiver) {
            // POST-CONDITIONS
            __afterAsp(cache.aspTKN, cache.spTKN, cache.user, cache.receiver);

            invariant_POD_34(shares);
            invariant_POD_38();
        } catch Error(string memory reason) {
            string[7] memory stringErrors = [
                "UniswapV2Router: INSUFFICIENT_A_AMOUNT",
                "UniswapV2Router: INSUFFICIENT_B_AMOUNT",
                "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT",
                "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT",
                "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED",
                "ERC20: transfer amount exceeds balance",
                "SafeERC20: decreased allowance below zero" // @audit added this
            ];

            bool expected = false;
            for (uint256 i = 0; i < stringErrors.length; i++) {
                if (compareStrings(stringErrors[i], reason)) {
                    expected = true;
                    break;
                }
            }

            if (
                compareStrings(reason, stringErrors[0]) || compareStrings(reason, stringErrors[1])
                    || compareStrings(reason, stringErrors[2]) || compareStrings(reason, stringErrors[3])
            ) {
                invariant_POD_39();
            } else if (compareStrings(reason, stringErrors[4])) {
                invariant_POD_40();
            }

            fl.t(expected, reason);
        }
    }

    struct WithdrawTemps {
        address user;
        address receiver;
        address aspTKNAsset;
        address aspTKNAddress;
        uint256 assets;
        StakingPoolToken spTKN;
        AutoCompoundingPodLp aspTKN;
    }

    function aspTKN_withdraw(uint256 userIndexSeed, uint256 receiverIndexSeed, uint256 aspTKNSeed, uint256 assets)
        public
    {
        // PRE-CONDITIONS
        WithdrawTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.aspTKN = randomAspTKN(aspTKNSeed);
        cache.aspTKNAddress = address(cache.aspTKN);
        cache.aspTKNAsset = cache.aspTKN.asset();
        cache.spTKN = StakingPoolToken(IDecentralizedIndex(cache.aspTKN.pod()).lpStakingPool());

        assets = fl.clamp(assets, 0, cache.aspTKN.maxWithdraw(cache.user));
        if (assets == 0 || cache.aspTKN.convertToShares(assets) == 0) return;

        __beforeAsp(cache.aspTKN, cache.spTKN, cache.user, cache.receiver);

        // ACTION
        vm.prank(cache.user);
        try cache.aspTKN.withdraw(assets, cache.receiver, cache.user) {
            // POST-CONDITIONS
            __afterAsp(cache.aspTKN, cache.spTKN, cache.user, cache.receiver);

            invariant_POD_37(assets);
            invariant_POD_38();
        } catch Error(string memory reason) {
            string[7] memory stringErrors = [
                "UniswapV2Router: INSUFFICIENT_A_AMOUNT",
                "UniswapV2Router: INSUFFICIENT_B_AMOUNT",
                "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT",
                "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT",
                "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED",
                "ERC20: transfer amount exceeds balance",
                "SafeERC20: decreased allowance below zero"
            ];

            bool expected = false;
            for (uint256 i = 0; i < stringErrors.length; i++) {
                if (compareStrings(stringErrors[i], reason)) {
                    expected = true;
                    break;
                }
            }

            if (
                compareStrings(reason, stringErrors[0]) || compareStrings(reason, stringErrors[1])
                    || compareStrings(reason, stringErrors[2]) || compareStrings(reason, stringErrors[3])
            ) {
                invariant_POD_39();
            } else if (compareStrings(reason, stringErrors[4])) {
                invariant_POD_40();
            } else if (compareStrings(reason, stringErrors[5])) {
                invariant_POD_41();
            }

            fl.t(expected, reason);
        }
    }

    struct RedeemTemps {
        address user;
        address receiver;
        address aspTKNAsset;
        address aspTKNAddress;
        uint256 assets;
        StakingPoolToken spTKN;
        AutoCompoundingPodLp aspTKN;
    }

    function aspTKN_redeem(uint256 userIndexSeed, uint256 receiverIndexSeed, uint256 aspTKNSeed, uint256 shares)
        public
    {
        // PRE-CONDITIONS
        RedeemTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.aspTKN = randomAspTKN(aspTKNSeed);
        cache.aspTKNAddress = address(cache.aspTKN);
        cache.aspTKNAsset = cache.aspTKN.asset();
        cache.spTKN = StakingPoolToken(IDecentralizedIndex(cache.aspTKN.pod()).lpStakingPool());

        shares = fl.clamp(shares, 0, cache.aspTKN.maxRedeem(cache.user));
        if (shares == 0) return;

        __beforeAsp(cache.aspTKN, cache.spTKN, cache.user, cache.receiver);

        // ACTION
        vm.prank(cache.user);
        try cache.aspTKN.redeem(shares, cache.receiver, cache.user) {
            // POST-CONDITIONS
            __afterAsp(cache.aspTKN, cache.spTKN, cache.user, cache.receiver);

            invariant_POD_36(shares);
            invariant_POD_38();
        } catch Error(string memory reason) {
            string[7] memory stringErrors = [
                "UniswapV2Router: INSUFFICIENT_A_AMOUNT",
                "UniswapV2Router: INSUFFICIENT_B_AMOUNT",
                "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT",
                "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT",
                "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED",
                "ERC20: transfer amount exceeds balance",
                "SafeERC20: decreased allowance below zero" // @audit added this
            ];

            bool expected = false;
            for (uint256 i = 0; i < stringErrors.length; i++) {
                if (compareStrings(stringErrors[i], reason)) {
                    expected = true;
                    break;
                }
            }

            if (
                compareStrings(reason, stringErrors[0]) || compareStrings(reason, stringErrors[1])
                    || compareStrings(reason, stringErrors[2]) || compareStrings(reason, stringErrors[3])
            ) {
                invariant_POD_39();
            } else if (compareStrings(reason, stringErrors[4])) {
                invariant_POD_40();
            } else if (compareStrings(reason, stringErrors[5])) {
                invariant_POD_41();
            }

            fl.t(expected, reason);
        }
    }
}

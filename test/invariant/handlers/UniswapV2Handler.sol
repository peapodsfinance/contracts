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
import {StakingPoolToken} from "../../../contracts/StakingPoolToken.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IUniswapV2Pair} from "v2-core/interfaces/IUniswapV2Pair.sol";

import {SafeMath} from "v2-core/libraries/SafeMath.sol";

contract UniswapV2Handler is Properties {
    using SafeMath for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                            UNISWAP V2 PAIR FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    // Trading staking pool token for pod token
    struct BuyTokenTemps {
        WeightedIndex pod;
        IUniswapV2Pair pair;
        address from;
        address to;
    }

    function stakingPoolLp_buyTokens(
        uint256 podIndexSeed,
        uint256 fromIndexSeed,
        uint256 toIndexSeed,
        uint256 amountIn
    ) public {
        // PRE-CONDITIONS
        BuyTokenTemps memory cache;
        cache.pod = randomPod(podIndexSeed);
        cache.from = randomAddress(fromIndexSeed);
        cache.to = randomAddress(toIndexSeed);
        cache.pair = IUniswapV2Pair(_dexAdapter.getV2Pool(address(cache.pod), cache.pod.PAIRED_LP_TOKEN()));

        address pairedToken = cache.pod.PAIRED_LP_TOKEN();
        address[] memory path = new address[](2);
        path[0] = address(pairedToken);
        path[1] = address(cache.pod);

        if (IERC20(pairedToken).balanceOf(cache.from) < 1e14) return;
        amountIn = fl.clamp(amountIn, 1e14, IERC20(pairedToken).balanceOf(cache.from));

        // ACTION
        vm.prank(cache.from);
        IERC20(pairedToken).approve(address(_v2SwapRouter), type(uint256).max);

        vm.prank(cache.from);
        // try 
        _v2SwapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, 0, path, cache.to, block.timestamp
         );
        //   {} catch {
        //     fl.t(false, "BUY TOKENS FAILED");
        //  }
         // catch (bytes memory err) {
        //     bytes4[2] memory errors =
        //         [g8keepToken.InsufficientBalance.selector, g8keepToken.InsufficientPoolInput.selector];
        //     bool expected = false;
        //     for (uint256 i = 0; i < errors.length; i++) {
        //         if (errors[i] == bytes4(err)) {
        //             expected = true;
        //             break;
        //         }
        //     }
        //     fl.t(expected, FuzzLibString.getRevertMsg(err));
        //     return;
        // }
    }

    // Trading pod token for staking pool token
    struct SellTokenTemps {
        WeightedIndex pod;
        IUniswapV2Pair pair;
        address from;
        address to;
    }

    function stakingPoolLp_sellTokens(
        uint256 podIndexSeed,
        uint256 fromIndexSeed,
        uint256 toIndexSeed,
        uint256 amountIn
    ) public {
        // PRE-CONDITIONS
        SellTokenTemps memory cache;
        cache.pod = randomPod(podIndexSeed);
        cache.from = randomAddress(fromIndexSeed);
        cache.to = randomAddress(toIndexSeed);
        cache.pair = IUniswapV2Pair(_dexAdapter.getV2Pool(address(cache.pod), cache.pod.PAIRED_LP_TOKEN()));

        address pairedToken = cache.pod.PAIRED_LP_TOKEN();
        address[] memory path = new address[](2);
        path[0] = address(cache.pod);
        path[1] = address(pairedToken);

        if (cache.pod.balanceOf(cache.from) < 1e14) return;
        amountIn = fl.clamp(amountIn, 1e14, cache.pod.balanceOf(cache.from));

        // ACTION
        vm.prank(cache.from);
        IERC20(path[0]).approve(address(_v2SwapRouter), type(uint256).max);

        vm.prank(cache.from);
        // try 
        _v2SwapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn, 0, path, cache.to, block.timestamp
        );
        //  {} catch {
        //     fl.t(false, "SELL TOKEN FAILED");
        // }
        // catch (bytes memory err) {
        //     bytes4[2] memory errors =
        //         [g8keepToken.InsufficientBalance.selector, g8keepToken.InsufficientPoolInput.selector];
        //     bool expected = false;
        //     for (uint256 i = 0; i < errors.length; i++) {
        //         if (errors[i] == bytes4(err)) {
        //             expected = true;
        //             break;
        //         }
        //     }
        //     fl.t(expected, FuzzLibString.getRevertMsg(err));
        //     return;
        // }
    }

    struct AddLiquidityLPTemps {
        WeightedIndex pod;
        IUniswapV2Pair pair;
        address from;
        address to;
        address pairedToken;
        uint112 reserve0;
        uint112 reserve1;
    }

    function stakingPoolLp_addLiquidity(
        uint256 podIndexSeed,
        uint256 fromIndexSeed,
        uint256 toIndexSeed,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) public {
        // PRE-CONDITIONS
        AddLiquidityLPTemps memory cache;
        cache.pod = randomPod(podIndexSeed);
        cache.from = randomAddress(fromIndexSeed);
        cache.to = randomAddress(toIndexSeed);
        cache.pairedToken = cache.pod.PAIRED_LP_TOKEN();
        cache.pair = IUniswapV2Pair(_dexAdapter.getV2Pool(address(cache.pod), cache.pairedToken));

        if (cache.pod.balanceOf(cache.from) < 1e14) return;

        amount1Desired = fl.clamp(amount1Desired, 1e14, cache.pod.balanceOf(cache.from));

        (cache.reserve0, cache.reserve1, ) = cache.pair.getReserves();

        if (cache.reserve0 == 0 || cache.reserve1 == 0) return;

        amount0Desired = amount1Desired.mul(cache.reserve0) / cache.reserve1;

        if (amount0Desired > IERC20(cache.pairedToken).balanceOf(cache.from) || amount1Desired == 0) {
            return;
        }

        vm.prank(cache.from);
        cache.pod.approve(address(_v2SwapRouter), type(uint256).max);
        vm.prank(cache.from);
        IERC20(cache.pairedToken).approve(address(_v2SwapRouter), type(uint256).max);
        // ACTION
        vm.prank(cache.from);
        // try 
        _v2SwapRouter.addLiquidity(
            cache.pairedToken, address(cache.pod), amount0Desired, amount1Desired, 0, 0, cache.to, block.timestamp
        );
        //  {} catch Error(string memory reason) {
            
        //     string[4] memory stringErrors = [
        //         "UniswapV2Router: INSUFFICIENT_A_AMOUNT",
        //         "UniswapV2Router: INSUFFICIENT_B_AMOUNT",
        //         "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT",
        //         "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED"
        //     ];

        //     bool expected = false;
        //     for (uint256 i = 0; i < stringErrors.length; i++) {
        //         if (compareStrings(stringErrors[i], reason)) {
        //             expected = true;
        //             break;
        //         }
        //     }
        //     fl.t(expected, reason);
        // }
    }

    struct RemoveLiquidityTemps {
        WeightedIndex pod;
        IUniswapV2Pair pair;
        address from;
        address to;
        address pairedToken;
        uint112 reserve0;
        uint112 reserve1;
        uint256 pairBalanceToken0;
        uint256 pairBalanceToken1;
    }

    function stakingPoolLp_removeLiquidity(
        uint256 podIndexSeed,
        uint256 fromIndexSeed,
        uint256 toIndexSeed,
        uint256 liquidity
    ) public {
        // PRE-CONDITIONS
        RemoveLiquidityTemps memory cache;
        cache.pod = randomPod(podIndexSeed);
        cache.pairedToken = cache.pod.PAIRED_LP_TOKEN();
        cache.pair = IUniswapV2Pair(_dexAdapter.getV2Pool(address(cache.pod), cache.pairedToken));
        cache.from = randomAddress(fromIndexSeed);
        cache.to = randomAddress(toIndexSeed);

        if (cache.pair.balanceOf(cache.from) < 1e14) return;
        liquidity = fl.clamp(liquidity, 1e14, cache.pair.balanceOf(cache.from));

        (cache.reserve0, cache.reserve1, ) = cache.pair.getReserves();
        if (cache.reserve0 == 0 || cache.reserve1 == 0) return;

        cache.pairBalanceToken0 = cache.pod.balanceOf(address(cache.pair));
        cache.pairBalanceToken1 = IERC20(cache.pairedToken).balanceOf(address(cache.pair));

        uint256 amount0 = liquidity.mul(cache.pairBalanceToken0) / cache.pair.totalSupply();
        uint256 amount1 = liquidity.mul(cache.pairBalanceToken1) / cache.pair.totalSupply();

        vm.prank(cache.from);
        cache.pair.approve(address(_v2SwapRouter), type(uint256).max);

        // ACTION
        vm.prank(cache.from);
        // try 
        _v2SwapRouter.removeLiquidity(
            cache.pairedToken, address(cache.pod), liquidity, 0, 0, cache.to, block.timestamp
        );
        //  {} catch {
        //     fl.t(false, "REMOVE LIQUIDITY FAILED");
        // }
        // catch (bytes memory err) {
        //     bytes4[2] memory errors =
        //         [g8keepToken.InsufficientBalance.selector, g8keepToken.InsufficientPoolInput.selector];
        //     bool expected = false;
        //     for (uint256 i = 0; i < errors.length; i++) {
        //         if (errors[i] == bytes4(err)) {
        //             expected = true;
        //             break;
        //         }
        //     }
        //     fl.t(expected, FuzzLibString.getRevertMsg(err));
        //     return;
        // } catch Error(string memory reason) {
        //     string[4] memory stringErrors = [
        //         "UniswapV2Router: INSUFFICIENT_A_AMOUNT",
        //         "UniswapV2Router: INSUFFICIENT_B_AMOUNT",
        //         "UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED",
        //         "UniswapV2: TRANSFER_FAILED"
        //     ];
        //     bool expected = false;
        //     for (uint256 i = 0; i < stringErrors.length; i++) {
        //         if (compareStrings(stringErrors[i], reason)) {
        //             expected = true;
        //             break;
        //         }
        //     }
        //     fl.t(expected, reason);
        //     return;
        // }
    }

    struct SyncTemps {
        WeightedIndex pod;
        address pairedToken;
        IUniswapV2Pair pair;
    }

    function g8keepToken_sync(uint256 podIndexSeed) public {
        // PRE-CONDITIONS
        SyncTemps memory cache;
        cache.pod = randomPod(podIndexSeed);
        cache.pairedToken = cache.pod.PAIRED_LP_TOKEN();
        cache.pair = IUniswapV2Pair(_dexAdapter.getV2Pool(address(cache.pod), cache.pairedToken));

        cache.pair.sync();
    }

    struct DonateLPTemps {
        WeightedIndex pod;
        IUniswapV2Pair pair;
        address pairedToken;
        address from;
        address token;
    }

    function stakingPoolLp_donate(
        uint256 podIndexSeed,
        uint256 fromIndexSeed,
        uint256 toIndexSeed,
        uint256 amount
    ) public {
        // PRE-CONDITIONS
        DonateLPTemps memory cache;
        cache.pod = randomPod(podIndexSeed);
        cache.pairedToken = cache.pod.PAIRED_LP_TOKEN();
        cache.pair = IUniswapV2Pair(_dexAdapter.getV2Pool(address(cache.pod), cache.pairedToken));
        cache.from = randomAddress(fromIndexSeed);
        cache.token = toIndexSeed % 2 == 0 ? address(cache.pod) : cache.pairedToken;

        if (amount == 0) return;
        if (cache.token == address(cache.pod)) {
            if (cache.pod.balanceOf(cache.from) < amount) return;
        } else {
            if (IERC20(cache.pairedToken).balanceOf(cache.from) < amount) return;
        }
        // ACTION
        vm.prank(cache.from);
        cache.token == address(cache.pod)
            ? cache.pod.transfer(address(cache.pair), amount)
            : IERC20(cache.pairedToken).transfer(address(cache.pair), amount);
    }
}
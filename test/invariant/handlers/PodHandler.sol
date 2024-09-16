// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Properties} from "../helpers/Properties.sol";

import {WeightedIndex} from "../../../contracts/WeightedIndex.sol";

import {IUniswapV2Pair} from "uniswap-v2/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {FullMath} from "v3-core/libraries/FullMath.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PodHandler is Properties {

    struct BondTemps {
        address user;
        WeightedIndex pod;
        address token;
    }
    function pod_bond(uint256 userIndexSeed, uint256 podIndexSeed, uint256 indexTokenSeed, uint256 amount) public {
        
        // PRE-CONDITIONS
        BondTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.pod = randomPod(podIndexSeed);
        cache.token = randomIndexToken(cache.pod, indexTokenSeed);

        amount = fl.clamp(amount, 0, IERC20(cache.token).balanceOf(cache.user));

        _approveIndexTokens(cache.pod, cache.user, amount);
        if (!_checkTokenBalances(cache.pod, cache.token, cache.user, amount)) return;

        // ACTION
        vm.prank(cache.user);
        try cache.pod.bond(
            cache.token,
            amount,
            0
        ) {} catch {
            fl.t(false, "BOND FAILED");
        }
    }

    struct DebondTemps{
        address user;
        WeightedIndex pod;
        address[] array1;
        uint8[] array2;
    }

    function pod_debond(uint256 userIndexSeed, uint256 podIndexSeed, uint256 amount) public {
        
        // PRE-CONDITIONS
        DebondTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.pod = randomPod(podIndexSeed);
        cache.array1 = new address[](0);
        cache.array2 = new uint8[](0);

        amount = fl.clamp(amount, 0, IERC20(cache.pod).balanceOf(cache.user));
        if (amount < 1e14) return;

        // ACTION
        vm.prank(cache.user);
        try cache.pod.debond(
            amount,
            cache.array1,
            cache.array2
        ) {
        } catch (bytes memory lowLevelData) {
            // If the external call fails with a low-level error
            fl.log("CODE", lowLevelData);
            // fl.t(false, "DEBOND FAILED");
        }
    }

    struct AddLiquidityTemps {
        address user;
        address pairedLpToken;
        address v2Pool;
        WeightedIndex pod;
    }

    function pod_addLiquidityV2(
        uint256 userIndexSeed,
        uint256 podIndexSeed,
        uint256 indexLpTokens,
        uint256 pairedLpTokens
        ) public {

        // PRE-CONDITIONS
        AddLiquidityTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.pod = randomPod(podIndexSeed);
        cache.pairedLpToken = cache.pod.PAIRED_LP_TOKEN();
        cache.v2Pool = _uniV2Factory.getPair(address(cache.pod), cache.pairedLpToken);

        fl.log("POD ADDRESS", address(cache.pod));
        fl.log("TOKEN 0", IUniswapV2Pair(cache.v2Pool).token0());
        fl.log("PAIRED TOKEN ADDRESS", cache.pairedLpToken);
        fl.log("TOKEN 1", IUniswapV2Pair(cache.v2Pool).token1());
        indexLpTokens = fl.clamp(indexLpTokens, 0, cache.pod.balanceOf(cache.user));

        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(cache.v2Pool).getReserves();
        
        address(cache.pod) < cache.pairedLpToken ? 
        pairedLpTokens = _v2SwapRouter.quote(indexLpTokens, reserve0, reserve1) : 
        pairedLpTokens = _v2SwapRouter.quote(indexLpTokens, reserve1, reserve0);

        if (indexLpTokens < 1000 || IERC20(cache.pairedLpToken).balanceOf(cache.user) < pairedLpTokens) return;

        vm.prank(cache.user);
        IERC20(cache.pairedLpToken).approve(address(cache.pod), pairedLpTokens);
        vm.prank(cache.user);
        cache.pod.approve(address(cache.pod), indexLpTokens);

        // ACTION
        vm.prank(cache.user);
        try cache.pod.addLiquidityV2(
            indexLpTokens,
            pairedLpTokens,
            100,
            block.timestamp
        ) {} catch {
            fl.t(false, "ADD LIQUIDITY FAILED");
        }
    }
}
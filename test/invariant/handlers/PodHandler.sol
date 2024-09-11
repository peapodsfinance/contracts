// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Properties} from "../helpers/Properties.sol";

import {WeightedIndex} from "../../../contracts/WeightedIndex.sol";

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
}
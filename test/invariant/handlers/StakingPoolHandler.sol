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

contract StakingPoolHandler is Properties {
    struct StakeTemps {
        address user;
        address stakingPool;
        address stakingToken;
        WeightedIndex pod;
    }

    function stakingPool_stake(uint256 userIndexSeed, uint256 podIndexSeed, uint256 amount) public {
        // PRE-CONDITIONS
        StakeTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.pod = randomPod(podIndexSeed);
        cache.stakingPool = cache.pod.lpStakingPool();
        cache.stakingToken = StakingPoolToken(cache.stakingPool).stakingToken();

        amount = fl.clamp(amount, 0, IERC20(cache.stakingToken).balanceOf(cache.user));
        if (amount <= 1000) return;

        vm.prank(cache.user);
        IERC20(cache.stakingToken).approve(cache.stakingPool, amount);

        // ACTION
        vm.prank(cache.user);
        try StakingPoolToken(cache.stakingPool).stake(cache.user, amount) {}
        catch {
            // fl.t(false, "STAKE FAILED");
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Properties} from "../helpers/Properties.sol";

import {WeightedIndex} from "../../../contracts/WeightedIndex.sol";
import {IDecentralizedIndex} from "../../../contracts/interfaces/IDecentralizedIndex.sol";
import {LeveragePositions} from "../../../contracts/lvf/LeveragePositions.sol";
import {ILeverageManager} from "../../../contracts/interfaces/ILeverageManager.sol";
import {IFlashLoanSource} from "../../../contracts/interfaces/IFlashLoanSource.sol";
import {AutoCompoundingPodLp} from "../../../contracts/AutoCompoundingPodLp.sol";

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
        AutoCompoundingPodLp aspTKN;
    }

    function aspTKN_deposit(uint256 userIndexSeed, uint256 receiverIndexSeed, uint256 aspTKNSeed, uint256 assets) public {

        // PRE-CONDITIONS
        DepositTemps memory cache;
        cache.user = randomAddress(userIndexSeed);
        cache.receiver = randomAddress(receiverIndexSeed);
        cache.aspTKN = randomAspTKN(aspTKNSeed);
        cache.aspTKNAddress = address(cache.aspTKN);
        cache.aspTKNAsset = cache.aspTKN.asset();

        assets = fl.clamp(assets, 0, IERC20(cache.aspTKNAsset).balanceOf(cache.user));
        if (assets == 0) return;

        vm.prank(cache.user);
        IERC20(cache.aspTKNAsset).approve(cache.aspTKNAddress, assets);

        // ACTION
        vm.prank(cache.user);
        try cache.aspTKN.deposit(assets, cache.receiver) {} catch {
            fl.t(false, "DEPOSIT FAILED");
        }
    }

    struct MintTemps {
        address user;
        address receiver;
        address aspTKNAsset;
        address aspTKNAddress;
        uint256 assets;
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

        shares = fl.clamp(shares, 0, cache.aspTKN.convertToShares(IERC20(cache.aspTKNAsset).balanceOf(cache.user)));
        if (shares == 0) return;

        cache.assets = cache.aspTKN.convertToAssets(shares);

        vm.prank(cache.user);
        IERC20(cache.aspTKNAsset).approve(cache.aspTKNAddress, cache.assets);

        // ACTION
        vm.prank(cache.user);
        try cache.aspTKN.mint(shares, cache.receiver) {} catch {
            fl.t(false, "MINT FAILED");
        }
    }
}
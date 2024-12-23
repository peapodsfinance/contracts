// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PodHandler} from "./handlers/PodHandler.sol";
import {LeverageManagerHandler} from "./handlers/LeverageManagerHandler.sol";
import {AutoCompoundingPodLpHandler} from "./handlers/AutoCompoundingPodLpHandler.sol";
import {StakingPoolHandler} from "./handlers/StakingPoolHandler.sol";
import {LendingAssetVaultHandler} from "./handlers/LendingAssetVaultHandler.sol";
import {FraxlendPairHandler} from "./handlers/FraxlendPairHandler.sol";
import {UniswapV2Handler} from "./handlers/UniswapV2Handler.sol";

contract PeapodsInvariant is
    PodHandler,
    LeverageManagerHandler,
    AutoCompoundingPodLpHandler,
    StakingPoolHandler,
    LendingAssetVaultHandler,
    FraxlendPairHandler,
    UniswapV2Handler
{
    constructor() payable {
        setup();
    }
}

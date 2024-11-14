// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "v3-periphery/base/SelfPermit.sol";
import "v3-periphery/base/PeripheryImmutableState.sol";

import "./interfaces/ISwapRouter02.sol";
import "./V2SwapRouter.sol";
import "./V3SwapRouter.sol";
import "./base/ApproveAndCall.sol";
import "./base/MulticallExtended.sol";

/// @title Uniswap V2 and V3 Swap Router
contract SwapRouter02 is ISwapRouter02, V2SwapRouter, V3SwapRouter, ApproveAndCall, MulticallExtended, SelfPermit {
    constructor(address _factoryV2, address factoryV3, address _positionManager, address _WETH9)
        ImmutableState(_factoryV2, _positionManager)
        PeripheryImmutableState(factoryV3, _WETH9)
    {}
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// uniswap-v3-core
import {UniswapV3Factory} from "v3-core/UniswapV3Factory.sol";
import {UniswapV3Pool} from "v3-core/UniswapV3Pool.sol";
import {IUniswapV3MintCallback} from "v3-core/interfaces/callback/IUniswapV3MintCallback.sol";

// uniswap-v3-periphery
import {SwapRouter} from "v3-periphery/SwapRouter.sol";
import {LiquidityManagement} from "v3-periphery/base/LiquidityManagement.sol";
import {PeripheryPayments} from "v3-periphery/base/PeripheryPayments.sol";
import {PoolAddress} from "v3-periphery/libraries/PoolAddress.sol";

// mocks
import {WETH9} from "./WETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./MockERC20.sol";

contract MockUniV3Minter is IUniswapV3MintCallback {
    constructor() {}

    function V3addLiquidity(UniswapV3Pool _pool, uint256 amount) public {
        PoolAddress.PoolKey memory poolKey =
            PoolAddress.PoolKey({token0: _pool.token0(), token1: _pool.token1(), fee: _pool.fee()});
        _pool.mint(
            msg.sender,
            -887200,
            887200,
            uint128(amount),
            abi.encode(LiquidityManagement.MintCallbackData({poolKey: poolKey, payer: address(this)}))
        );
    }

    event MessageUint(string a, uint256 b);
    event MessageAddress(string a, address b);

    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external override {
        emit MessageUint("amount0Owed", amount0Owed);
        emit MessageUint("amount1Owed", amount1Owed);

        LiquidityManagement.MintCallbackData memory decoded = abi.decode(data, (LiquidityManagement.MintCallbackData));

        emit MessageUint("Balance Token0", IERC20(decoded.poolKey.token0).balanceOf(address(this)));
        emit MessageUint("Balance Token1", IERC20(decoded.poolKey.token1).balanceOf(address(this)));

        emit MessageAddress("Token0", decoded.poolKey.token0);
        emit MessageAddress("Token1", decoded.poolKey.token1);

        if (amount0Owed > 0) IERC20(decoded.poolKey.token0).transfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) IERC20(decoded.poolKey.token1).transfer(msg.sender, amount1Owed);
    }
}

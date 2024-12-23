// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import "../contracts/libraries/TickMath.sol";

contract UniV3LP is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address recipient = vm.addr(deployerPrivateKey);

        address nonfungiblePositionManager = vm.envAddress("MANAGER");

        address t0 = vm.envAddress("T0");
        address t1 = vm.envAddress("T1");
        uint256 fee = vm.envUint("FEE");
        uint256 sqrtPriceX96 = vm.envUint("PRICEX96");

        (t0, t1) = t0 < t1 ? (t0, t1) : (t1, t0);
        uint256 bal0 = IERC20(t0).balanceOf(recipient);
        uint256 bal1 = IERC20(t1).balanceOf(recipient);

        address pool = INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(
            t0, t1, uint24(fee), uint160(sqrtPriceX96)
        );
        int24 _offset = TickMath.MAX_TICK % IUniswapV3Pool(pool).tickSpacing();

        IERC20(t0).approve(nonfungiblePositionManager, bal0);
        IERC20(t1).approve(nonfungiblePositionManager, bal1);
        INonfungiblePositionManager(nonfungiblePositionManager).mint(
            INonfungiblePositionManager.MintParams({
                token0: t0,
                token1: t1,
                fee: uint24(fee),
                tickLower: TickMath.MIN_TICK + _offset,
                tickUpper: TickMath.MAX_TICK - _offset,
                amount0Desired: bal0 / 10,
                amount1Desired: bal1 / 10,
                amount0Min: 0,
                amount1Min: 0,
                recipient: recipient,
                deadline: block.timestamp + 1 days
            })
        );

        vm.stopBroadcast();

        console.log("Successfully LPd");
    }
}

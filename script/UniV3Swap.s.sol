// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../contracts/interfaces/ISwapRouter02.sol";

contract UniV3Swap is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address recipient = vm.addr(deployerPrivateKey);

        address router = vm.envAddress("ROUTER");
        address source = vm.envAddress("SOURCE");
        address targetToken = vm.envAddress("TARGET");
        uint256 fee = vm.envUint("FEE");
        uint256 amountIn = vm.envUint("AMOUNT");

        IERC20(source).approve(router, amountIn);
        uint256 amountOut = ISwapRouter02(router).exactInputSingle(
            ISwapRouter02.ExactInputSingleParams({
                tokenIn: source,
                tokenOut: targetToken,
                fee: uint24(fee),
                recipient: recipient,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        vm.stopBroadcast();

        console.log("Successfully swapped and received:", amountOut);
    }
}

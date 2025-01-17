// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/twaputils/V3TwapUtilities.sol";
import "../../contracts/interfaces/IUniswapV3Pool.sol";
import "../../contracts/interfaces/IERC20Metadata.sol";

contract V3TwapUtilitiesTest is Test {
    V3TwapUtilities public twapUtils;

    // Mainnet addresses
    address public constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    uint24 public constant POOL_FEE = 3000; // 0.3%

    // Mainnet pools
    IUniswapV3Pool public wethUsdcPool;
    IUniswapV3Pool public wbtcWethPool;

    function setUp() public {
        // Deploy TWAP utilities
        twapUtils = new V3TwapUtilities();

        // Get pool addresses
        address wethUsdcPoolAddr = twapUtils.getV3Pool(FACTORY, WETH, USDC, POOL_FEE);
        address wbtcWethPoolAddr = twapUtils.getV3Pool(FACTORY, WBTC, WETH, POOL_FEE);

        // Initialize pool interfaces
        wethUsdcPool = IUniswapV3Pool(wethUsdcPoolAddr);
        wbtcWethPool = IUniswapV3Pool(wbtcWethPoolAddr);

        // Verify pools exist and are initialized
        require(address(wethUsdcPool).code.length > 0, "WETH/USDC pool not deployed");
        require(address(wbtcWethPool).code.length > 0, "WBTC/WETH pool not deployed");
    }

    function test_getV3Pool() public {
        address poolAddr = twapUtils.getV3Pool(FACTORY, WETH, USDC, POOL_FEE);
        assertTrue(poolAddr != address(0));
        assertTrue(poolAddr.code.length > 0);

        // Test with reversed token order
        address reversedPool = twapUtils.getV3Pool(FACTORY, USDC, WETH, POOL_FEE);
        assertEq(poolAddr, reversedPool);
    }

    function test_getV3Pool_Revert_WithTick() public {
        vm.expectRevert(bytes("I0"));
        twapUtils.getV3Pool(FACTORY, WETH, USDC, int24(1));
    }

    function test_getV3Pool_Revert_NoFee() public {
        vm.expectRevert(bytes("I1"));
        twapUtils.getV3Pool(FACTORY, WETH, USDC);
    }

    function test_getV3Pool_WithFee() public {
        address poolAddr = twapUtils.getV3Pool(FACTORY, WETH, USDC, uint24(POOL_FEE));
        assertTrue(poolAddr != address(0));
        assertTrue(poolAddr.code.length > 0);
    }

    function test_sqrtPriceX96FromPoolAndInterval() public {
        uint160 sqrtPrice = twapUtils.sqrtPriceX96FromPoolAndInterval(address(wethUsdcPool));
        assertTrue(sqrtPrice > 0);

        // Get current price to verify it's reasonable
        (uint160 currentSqrtPriceX96,,,,,,) = wethUsdcPool.slot0();
        assertApproxEqRel(sqrtPrice, currentSqrtPriceX96, 1e16); // 1% tolerance
    }

    function test_sqrtPriceX96FromPoolAndPassedInterval() public {
        uint32 interval = 300; // 5 minutes
        uint160 sqrtPrice = twapUtils.sqrtPriceX96FromPoolAndPassedInterval(address(wethUsdcPool), interval);
        assertTrue(sqrtPrice > 0);

        // Get current price to verify it's in a reasonable range
        (uint160 currentSqrtPriceX96,,,,,,) = wethUsdcPool.slot0();
        // Allow for more deviation since this is a TWAP
        assertApproxEqRel(sqrtPrice, currentSqrtPriceX96, 1e17); // 10% tolerance
    }

    function test_priceX96FromSqrtPriceX96() public {
        // Test with known values
        uint160 sqrtPriceX96 = 2 << 96; // 4.0 price when squared
        uint256 priceX96 = twapUtils.priceX96FromSqrtPriceX96(sqrtPriceX96);
        assertEq(priceX96, 4 << 96);

        // Test with real pool price
        (uint160 currentSqrtPriceX96,,,,,,) = wethUsdcPool.slot0();
        uint256 realPriceX96 = twapUtils.priceX96FromSqrtPriceX96(currentSqrtPriceX96);
        assertTrue(realPriceX96 > 0);
    }

    function test_getPoolPriceUSDX96() public {
        // Get WBTC/USD price through WBTC/WETH and WETH/USDC pools
        uint256 wbtcUsdPrice = twapUtils.getPoolPriceUSDX96(address(wbtcWethPool), address(wethUsdcPool), WETH);
        assertTrue(wbtcUsdPrice > 0);

        // Test same pool case (WETH/USDC)
        uint256 ethUsdPrice = twapUtils.getPoolPriceUSDX96(address(wethUsdcPool), address(wethUsdcPool), WETH);
        assertTrue(ethUsdPrice > 0);

        // WBTC should be worth more USD than ETH
        assertTrue(wbtcUsdPrice > ethUsdPrice);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import "../../contracts/oracle/UniswapV3SinglePriceOracle.sol";
import "forge-std/console.sol";

contract UniswapV3SinglePriceOracleTest is Test {
    UniswapV3SinglePriceOracle public oracle;

    function setUp() public {
        oracle = new UniswapV3SinglePriceOracle(address(0));
    }

    function test_getPriceUSD18_PEASDAI_NoCL() public view {
        (bool _isBadData, uint256 _price) = oracle.getPriceUSD18(
            address(0),
            0x02f92800F57BCD74066F5709F1Daa1A4302Df875, // PEAS
            0xAe750560b09aD1F5246f3b279b3767AfD1D79160, // PEAS / DAI
            10 minutes
        );
        console.log("DAI per PEAS via PEAS/DAI UniV3 pool price (no conversion from DAI to USD)", _price);
        assertEq(_isBadData, false);
        assertGt(_price, 2 * 10 ** 18); // greater than 2 (please god)
    }

    function test_getPriceUSD18_PEASDAI() public view {
        (bool _isBadData, uint256 _price) = oracle.getPriceUSD18(
            0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9, // CL: DAI / USD
            0x02f92800F57BCD74066F5709F1Daa1A4302Df875, // PEAS
            0xAe750560b09aD1F5246f3b279b3767AfD1D79160, // PEAS / DAI
            10 minutes
        );
        console.log("USD per PEAS via PEAS/DAI UniV3 pool price", _price);
        assertEq(_isBadData, false);
        assertGt(_price, 2 * 10 ** 18); // greater than 2 (please god)
    }

    function test_getPriceUSD18_PEASWETH() public view {
        (bool _isBadData, uint256 _price) = oracle.getPriceUSD18(
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, // CL: ETH / USD
            0x02f92800F57BCD74066F5709F1Daa1A4302Df875, // PEAS
            0x44C95bf226A6A1385beacED2bb3328D6aFb044a3, // PEAS / WETH
            10 minutes
        );
        console.log("USD per PEAS via PEAS/WETH UniV3 pool price", _price);
        assertEq(_isBadData, false);
        assertGt(_price, 2 * 10 ** 18); // greater than 2 (please god)
    }
}

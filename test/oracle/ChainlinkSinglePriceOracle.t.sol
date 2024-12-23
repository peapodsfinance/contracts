// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import "../../contracts/oracle/ChainlinkSinglePriceOracle.sol";
import "forge-std/console.sol";

contract ChainlinkSinglePriceOracleTest is Test {
    ChainlinkSinglePriceOracle public oracle;

    function setUp() public {
        oracle = new ChainlinkSinglePriceOracle(address(0));
    }

    function test_getPriceUSD18_quoteOnly() public view {
        (bool _isBadData, uint256 _price) = oracle.getPriceUSD18(
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, // ETH / USD
            address(0),
            address(0),
            0
        );
        console.log("USD per ETH price", _price);
        assertEq(_isBadData, false);
        assertGt(_price, 10 ** 21); // greater than $1000 (please god)
    }

    function test_getPriceUSD18_quoteAndBase() public view {
        (bool _isBadData, uint256 _price) = oracle.getPriceUSD18(
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, // ETH / USD
            0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // BTC / USD
            address(0),
            0
        );
        console.log("BTC per ETH price", _price);
        assertEq(_isBadData, false);
        assertGt(_price, 10 ** 16); // greater than 0.01 (please god again for the ETH bulls)
    }
}

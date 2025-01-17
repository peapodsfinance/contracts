// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/RewardsWhitelist.sol";

contract RewardsWhitelistTest is Test {
    RewardsWhitelist public whitelist;
    address public owner;
    address public user;
    address public token1;
    address public token2;

    function setUp() public {
        owner = address(this);
        user = address(0x1);
        token1 = address(0x2);
        token2 = address(0x3);
        whitelist = new RewardsWhitelist();
    }

    function testInitialState() public view {
        assertEq(whitelist.owner(), owner);
        assertEq(whitelist.getFullWhitelist().length, 0);
        assertFalse(whitelist.isWhitelistedFromDebondFee(token1));
        assertFalse(whitelist.paused(token1));
        assertFalse(whitelist.whitelist(token1));
    }

    function testSetOmitFromDebondFees() public {
        whitelist.setOmitFromDebondFees(token1, true);
        assertTrue(whitelist.isWhitelistedFromDebondFee(token1));

        whitelist.setOmitFromDebondFees(token1, false);
        assertFalse(whitelist.isWhitelistedFromDebondFee(token1));
    }

    function testSetOmitFromDebondFeesOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        whitelist.setOmitFromDebondFees(token1, true);
    }

    function testSetOmitFromDebondFeesSameValue() public {
        whitelist.setOmitFromDebondFees(token1, true);
        vm.expectRevert();
        whitelist.setOmitFromDebondFees(token1, true);
    }

    function testSetPaused() public {
        whitelist.setPaused(token1, true);
        assertTrue(whitelist.paused(token1));

        whitelist.setPaused(token1, false);
        assertFalse(whitelist.paused(token1));
    }

    function testSetPausedOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        whitelist.setPaused(token1, true);
    }

    function testSetPausedSameValue() public {
        whitelist.setPaused(token1, true);
        vm.expectRevert();
        whitelist.setPaused(token1, true);
    }

    function testToggleRewardsToken() public {
        // Add token1 to whitelist
        whitelist.toggleRewardsToken(token1, true);
        assertTrue(whitelist.whitelist(token1));
        assertEq(whitelist.getFullWhitelist().length, 1);
        assertEq(whitelist.getFullWhitelist()[0], token1);

        // Remove token1 from whitelist
        whitelist.toggleRewardsToken(token1, false);
        assertFalse(whitelist.whitelist(token1));
        assertEq(whitelist.getFullWhitelist().length, 0);
    }

    function testToggleRewardsTokenOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        whitelist.toggleRewardsToken(token1, true);
    }

    function testToggleRewardsTokenSameValue() public {
        whitelist.toggleRewardsToken(token1, true);
        vm.expectRevert();
        whitelist.toggleRewardsToken(token1, true);
    }

    function testToggleRewardsTokenMaxLimit() public {
        // Add MAX tokens
        for (uint8 i = 0; i < 12; i++) {
            whitelist.toggleRewardsToken(address(uint160(i + 1)), true);
        }

        // Try to add one more
        vm.expectRevert();
        whitelist.toggleRewardsToken(address(uint160(13)), true);

        // Remove one and add another should work
        whitelist.toggleRewardsToken(address(uint160(1)), false);
        whitelist.toggleRewardsToken(address(uint160(13)), true);
    }

    function testToggleRewardsTokenOrder() public {
        // Add three tokens
        whitelist.toggleRewardsToken(token1, true);
        whitelist.toggleRewardsToken(token2, true);
        address token3 = address(0x4);
        whitelist.toggleRewardsToken(token3, true);

        // Remove middle token
        whitelist.toggleRewardsToken(token2, false);

        // Verify array order
        address[] memory list = whitelist.getFullWhitelist();
        assertEq(list.length, 2);
        assertEq(list[0], token1);
        assertEq(list[1], token3);
    }
}

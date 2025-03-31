// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/PodUnwrapLocker.sol";

// Helper contract to expose the internal function for testing
contract PodUnwrapLockerExposed is PodUnwrapLocker {
    constructor(address _feeRecipient) PodUnwrapLocker(_feeRecipient) {}

    // Expose the internal function for testing
    function doesAddressArrayHaveDup(address[] memory _ary) public pure returns (bool) {
        return _doesAddressArrayHaveDup(_ary);
    }
}

contract PodUnwrapLockerDupCheckTest is Test {
    PodUnwrapLockerExposed public locker;

    function setUp() public {
        locker = new PodUnwrapLockerExposed(address(0x1));
    }

    function testDoesAddressArrayHaveDup_NoDuplicates() public view {
        // Create an array with no duplicates
        address[] memory addresses = new address[](3);
        addresses[0] = address(0x1);
        addresses[1] = address(0x2);
        addresses[2] = address(0x3);

        // Check that the function correctly identifies no duplicates
        bool hasDup = locker.doesAddressArrayHaveDup(addresses);
        assertFalse(hasDup, "Array with no duplicates should return false");
    }

    function testDoesAddressArrayHaveDup_WithDuplicates() public view {
        // Create an array with duplicates
        address[] memory addresses = new address[](3);
        addresses[0] = address(0x1);
        addresses[1] = address(0x2);
        addresses[2] = address(0x1); // Duplicate of first address

        // Check that the function correctly identifies duplicates
        bool hasDup = locker.doesAddressArrayHaveDup(addresses);
        assertTrue(hasDup, "Array with duplicates should return true");
    }

    function testDoesAddressArrayHaveDup_EmptyArray() public view {
        // Create an empty array
        address[] memory addresses = new address[](0);

        // Check that the function handles empty arrays correctly
        bool hasDup = locker.doesAddressArrayHaveDup(addresses);
        assertFalse(hasDup, "Empty array should return false");
    }

    function testDoesAddressArrayHaveDup_SingleElement() public view {
        // Create an array with a single element
        address[] memory addresses = new address[](1);
        addresses[0] = address(0x1);

        // Check that the function handles single-element arrays correctly
        bool hasDup = locker.doesAddressArrayHaveDup(addresses);
        assertFalse(hasDup, "Single-element array should return false");
    }

    function testDoesAddressArrayHaveDup_AllSameElements() public view {
        // Create an array where all elements are the same
        address[] memory addresses = new address[](3);
        addresses[0] = address(0x1);
        addresses[1] = address(0x1);
        addresses[2] = address(0x1);

        // Check that the function correctly identifies duplicates
        bool hasDup = locker.doesAddressArrayHaveDup(addresses);
        assertTrue(hasDup, "Array with all same elements should return true");
    }
}

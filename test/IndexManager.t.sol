// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/IndexManager.sol";
import "../contracts/interfaces/IWeightedIndexFactory.sol";
import "../contracts/interfaces/IDecentralizedIndex.sol";
import "./mocks/TestERC20.sol";

contract MockWeightedIndexFactory is IWeightedIndexFactory {
    function deployPodAndLinkDependencies(string memory, string memory, bytes memory, bytes memory)
        external
        returns (address pod, address vault, address rewards)
    {
        // Return dummy addresses for testing
        return (address(new TestERC20("Pod", "POD")), address(0), address(0));
    }
}

contract IndexManagerTest is Test {
    IndexManager public manager;
    MockWeightedIndexFactory public factory;
    address public owner;
    address public authorized;
    address public unauthorized;
    address public index1;
    address public index2;
    address public index3;

    event AddIndex(address indexed index, bool verified);
    event RemoveIndex(address indexed index);
    event SetVerified(address indexed index, bool verified);

    function setUp() public {
        owner = address(this);
        authorized = address(0xA);
        unauthorized = address(0xB);

        factory = new MockWeightedIndexFactory();
        manager = new IndexManager(factory);

        // Create some test indexes
        index1 = address(new TestERC20("Index1", "IDX1"));
        index2 = address(new TestERC20("Index2", "IDX2"));
        index3 = address(new TestERC20("Index3", "IDX3"));
    }

    function test_InitialState() public view {
        assertEq(address(manager.podFactory()), address(factory));
        assertEq(manager.owner(), owner);
        assertEq(manager.indexLength(), 0);
    }

    function test_Authorization() public {
        // Test authorization controls
        assertFalse(manager.authorized(authorized));
        manager.setAuthorized(authorized, true);
        assertTrue(manager.authorized(authorized));

        // Test authorization revocation
        manager.setAuthorized(authorized, false);
        assertFalse(manager.authorized(authorized));

        // Test unauthorized access should fail
        vm.startPrank(unauthorized);
        vm.expectRevert();
        manager.addIndex(index1, unauthorized, false, false, false);
        vm.stopPrank();
    }

    function test_AddIndex() public {
        // Add first index
        manager.addIndex(index1, owner, true, false, true);
        assertEq(manager.indexLength(), 1);

        // Verify index data
        IIndexManager.IIndexAndStatus[] memory indexes = manager.allIndexes();
        assertEq(indexes[0].index, index1);
        assertEq(indexes[0].creator, owner);
        assertTrue(indexes[0].verified);
        assertFalse(indexes[0].selfLending);
        assertTrue(indexes[0].makePublic);

        // Add second index
        manager.addIndex(index2, authorized, false, true, false);
        assertEq(manager.indexLength(), 2);

        // Verify both indexes
        indexes = manager.allIndexes();
        assertEq(indexes[1].index, index2);
        assertEq(indexes[1].creator, authorized);
        assertFalse(indexes[1].verified);
        assertTrue(indexes[1].selfLending);
        assertFalse(indexes[1].makePublic);
    }

    function test_RemoveIndex() public {
        // Add three indexes
        manager.addIndex(index1, owner, true, false, true);
        manager.addIndex(index2, authorized, false, true, false);
        manager.addIndex(index3, owner, true, true, true);
        assertEq(manager.indexLength(), 3);

        // Remove middle index
        manager.removeIndex(1);
        assertEq(manager.indexLength(), 2);

        // Verify remaining indexes and their order
        IIndexManager.IIndexAndStatus[] memory indexes = manager.allIndexes();
        assertEq(indexes[0].index, index1);
        assertEq(indexes[1].index, index3); // index3 should have moved to index2's position

        // Verify internal mapping is updated
        vm.expectRevert(); // Should revert when trying to verify removed index
        manager.verifyIndex(2, true);
    }

    function test_DeployNewIndex() public {
        string memory name = "Test Index";
        string memory symbol = "TIDX";
        IDecentralizedIndex.Config memory config;
        IDecentralizedIndex.Fees memory fees;
        address[] memory tokens = new address[](2);
        uint256[] memory weights = new uint256[](2);

        tokens[0] = address(0x1);
        tokens[1] = address(0x2);
        weights[0] = 5000;
        weights[1] = 5000;

        manager.deployNewIndex(name, symbol, abi.encode(config, fees, tokens, weights, address(0), false), "");

        assertEq(manager.indexLength(), 1);
    }

    function test_UpdateIndexProperties() public {
        // Add an index
        manager.addIndex(index1, owner, false, false, false);

        // Test updating makePublic
        manager.updateMakePublic(index1, true);
        IIndexManager.IIndexAndStatus[] memory indexes = manager.allIndexes();
        assertTrue(indexes[0].makePublic);

        // Test updating selfLending
        manager.updateSelfLending(index1, true);
        indexes = manager.allIndexes();
        assertTrue(indexes[0].selfLending);

        // Test verifying index
        manager.verifyIndex(0, true);
        indexes = manager.allIndexes();
        assertTrue(indexes[0].verified);
    }

    function test_CreatorPermissions() public {
        address creator = address(0xC);

        // Add index with specific creator
        manager.addIndex(index1, creator, false, false, false);

        // Creator should be able to update their index properties
        vm.startPrank(creator);
        manager.updateMakePublic(index1, true);
        manager.updateSelfLending(index1, true);
        vm.stopPrank();

        // Unauthorized user should not be able to update
        vm.startPrank(unauthorized);
        vm.expectRevert();
        manager.updateMakePublic(index1, false);
        vm.expectRevert();
        manager.updateSelfLending(index1, false);
        vm.stopPrank();
    }

    function test_RevertConditions() public {
        // Test duplicate authorization change
        manager.setAuthorized(authorized, true);
        vm.expectRevert();
        manager.setAuthorized(authorized, true);

        // Add an index for testing updates
        manager.addIndex(index1, owner, false, false, false);

        // Test duplicate makePublic update
        manager.updateMakePublic(index1, true);
        vm.expectRevert();
        manager.updateMakePublic(index1, true);

        // Test duplicate selfLending update
        manager.updateSelfLending(index1, true);
        vm.expectRevert();
        manager.updateSelfLending(index1, true);

        // Test duplicate verified update
        manager.verifyIndex(0, true);
        vm.expectRevert();
        manager.verifyIndex(0, true);
    }

    function test_InternalMappingIntegrity() public {
        // Add multiple indexes
        manager.addIndex(index1, owner, false, false, false);
        manager.addIndex(index2, owner, false, false, false);
        manager.addIndex(index3, owner, false, false, false);

        // Remove middle index
        manager.removeIndex(1);

        // Verify we can still update the last index that was moved
        manager.updateMakePublic(index3, true);
        IIndexManager.IIndexAndStatus[] memory indexes = manager.allIndexes();
        assertTrue(indexes[1].makePublic); // index3 should now be at position 1

        // Add new index after removal
        address index4 = address(new TestERC20("Index4", "IDX4"));
        manager.addIndex(index4, owner, false, false, false);

        // Verify all indexes are accessible
        indexes = manager.allIndexes();
        assertEq(indexes.length, 3);
        assertEq(indexes[0].index, index1);
        assertEq(indexes[1].index, index3);
        assertEq(indexes[2].index, index4);
    }

    function test_SetFactory() public {
        address newFactory = address(new MockWeightedIndexFactory());
        manager.setFactory(IWeightedIndexFactory(newFactory));
        assertEq(address(manager.podFactory()), newFactory);
    }

    function test_EmitEvents() public {
        // Test AddIndex event
        vm.expectEmit(true, false, false, true);
        emit AddIndex(index1, true);
        manager.addIndex(index1, owner, true, false, false);

        // Test RemoveIndex event
        vm.expectEmit(true, false, false, true);
        emit RemoveIndex(index1);
        manager.removeIndex(0);

        // Test SetVerified event
        manager.addIndex(index2, owner, false, false, false);
        vm.expectEmit(true, false, false, true);
        emit SetVerified(index2, true);
        manager.verifyIndex(0, true);
    }
}

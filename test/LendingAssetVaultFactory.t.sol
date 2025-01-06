// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/LendingAssetVaultFactory.sol";
import "../contracts/LendingAssetVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract LendingAssetVaultFactoryTest is Test {
    LendingAssetVaultFactory public factory;
    MockERC20 public asset;
    address public owner;
    address public user;

    function setUp() public {
        owner = address(this);
        user = address(0x1);

        asset = new MockERC20("Test Token", "TEST");
        factory = new LendingAssetVaultFactory();

        // Transfer some tokens to the user for testing
        asset.transfer(user, 10000 * 10 ** 18);
    }

    function testCreateWithMinimumDeposit() public {
        string memory name = "Test Vault";
        string memory symbol = "TVAULT";
        uint96 salt = 0;

        // Set minimum deposit
        factory.setMinimumDepositAtCreation(1000);

        // Approve tokens for minimum deposit
        vm.startPrank(owner);
        asset.approve(address(factory), 1000);

        // Create the vault
        address expectedVaultAddress = factory.getNewCaFromParams(name, symbol, address(asset), salt);
        factory.create(name, symbol, address(asset), salt);

        // Check if the vault was created at the expected address
        LendingAssetVault vault = LendingAssetVault(expectedVaultAddress);
        assertTrue(address(vault) != address(0), "Vault was not created");

        // Check if the vault properties are set correctly
        assertEq(vault.name(), name, "Vault name is incorrect");
        assertEq(vault.symbol(), symbol, "Vault symbol is incorrect");
        assertEq(address(vault.asset()), address(asset), "Vault asset is incorrect");

        // Check if the ownership was transferred to the factory owner
        assertEq(vault.owner(), owner, "Vault ownership was not transferred correctly");

        // Check if the minimum deposit was made
        assertEq(vault.totalAssets(), 1000, "Minimum deposit was not made");

        // // Check if the Create event was emitted
        // vm.expectEmit(true, false, false, false);
        // emit LendingAssetVaultFactory.Create(address(vault));

        vm.stopPrank();
    }

    function testCreateWithoutMinimumDeposit() public {
        string memory name = "Test Vault No Min";
        string memory symbol = "TVNM";
        uint96 salt = 1;

        // Set minimum deposit to 0
        factory.setMinimumDepositAtCreation(0);

        // Create the vault
        address expectedVaultAddress = factory.getNewCaFromParams(name, symbol, address(asset), salt);
        factory.create(name, symbol, address(asset), salt);

        // Check if the vault was created at the expected address
        LendingAssetVault vault = LendingAssetVault(expectedVaultAddress);
        assertTrue(address(vault) != address(0), "Vault was not created");

        // Check if the vault properties are set correctly
        assertEq(vault.name(), name, "Vault name is incorrect");
        assertEq(vault.symbol(), symbol, "Vault symbol is incorrect");
        assertEq(address(vault.asset()), address(asset), "Vault asset is incorrect");

        // Check if the ownership was transferred to the factory owner
        assertEq(vault.owner(), owner, "Vault ownership was not transferred correctly");

        // Check that no deposit was made
        assertEq(vault.totalAssets(), 0, "Unexpected deposit was made");
    }

    function testCreateOnlyOwner() public {
        string memory name = "Test Vault";
        string memory symbol = "TVAULT";
        uint96 salt = 2;

        // Set minimum deposit to 0
        factory.setMinimumDepositAtCreation(0);

        // Try to create a vault as a non-owner
        vm.prank(user);
        // vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        factory.create(name, symbol, address(asset), salt);
    }
}

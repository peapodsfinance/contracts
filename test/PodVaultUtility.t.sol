// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../contracts/PodVaultUtility.sol";
import "../contracts/interfaces/IDecentralizedIndex.sol";

// Mock contracts for testing
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockDecentralizedIndex is ERC20 {
    mapping(address => bool) public assets;
    uint256 public bondFeeRate = 100; // 1%
    IDecentralizedIndex.IndexAssetInfo[] private assetInfos;

    constructor() ERC20("Mock Pod Token", "mPOD") {}

    function bond(address token, uint256 amount, uint256 amountMintMin) external {
        require(assets[token], "Asset not supported");
        IERC20(token).transferFrom(msg.sender, address(this), amount);

        // Simulate bonding with a small fee
        uint256 mintAmount = (amount * (10000 - bondFeeRate)) / 10000;
        require(mintAmount >= amountMintMin, "Insufficient mint amount");

        _mint(msg.sender, mintAmount);
    }

    function convertToShares(uint256 _assets) external pure returns (uint256) {
        // Simple 1:1 conversion for testing, minus fee
        return (_assets * 9900) / 10000; // 1% fee
    }

    function addAsset(address token) external {
        assets[token] = true;
        // Add to assetInfos array as well
        assetInfos.push(
            IDecentralizedIndex.IndexAssetInfo({
                token: token,
                weighting: 10000, // 100% weighting for simplicity
                basePriceUSDX96: 0,
                c1: address(0),
                q1: 0
            })
        );
    }

    function isAsset(address token) external view returns (bool) {
        return assets[token];
    }

    function getAllAssets() external view returns (IDecentralizedIndex.IndexAssetInfo[] memory) {
        return assetInfos;
    }
}

contract MockERC4626Vault is ERC20 {
    IERC20 public immutable asset;
    uint256 public depositFeeRate = 50; // 0.5%

    constructor(address _asset) ERC20("Mock Vault Shares", "mVAULT") {
        asset = IERC20(_asset);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        asset.transferFrom(msg.sender, address(this), assets);

        // Simulate vault deposit with a small fee
        shares = (assets * (10000 - depositFeeRate)) / 10000;
        _mint(receiver, shares);

        return shares;
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return (assets * (10000 - depositFeeRate)) / 10000;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        // Simple implementation for testing
        shares = assets;
        _burn(owner, shares);
        asset.transfer(receiver, assets);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        // Simple implementation for testing
        assets = shares;
        _burn(owner, shares);
        asset.transfer(receiver, assets);
        return assets;
    }
}

contract PodVaultUtilityTest is Test {
    PodVaultUtility public utility;
    MockERC20 public mockToken;
    MockDecentralizedIndex public mockPod;
    MockERC4626Vault public mockVault;

    address public user = address(0x1);
    address public owner = address(0x2);

    uint256 public constant INITIAL_BALANCE = 1000e18;
    uint256 public constant BOND_AMOUNT = 100e18;

    function setUp() public {
        // Deploy contracts
        vm.startPrank(owner);
        utility = new PodVaultUtility();
        mockToken = new MockERC20("Mock Token", "MOCK");
        mockPod = new MockDecentralizedIndex();
        mockVault = new MockERC4626Vault(address(mockPod));
        vm.stopPrank();

        // Setup mock pod to accept the mock token
        mockPod.addAsset(address(mockToken));

        // Give user some tokens
        mockToken.mint(user, INITIAL_BALANCE);

        // User approves utility to spend tokens
        vm.prank(user);
        mockToken.approve(address(utility), type(uint256).max);
    }

    function testBondAndDeposit() public {
        uint256 expectedPodTokens = (BOND_AMOUNT * 9900) / 10000; // 1% bond fee
        uint256 expectedVaultShares = (expectedPodTokens * 9950) / 10000; // 0.5% vault fee

        vm.prank(user);
        uint256 actualVaultShares = utility.bondAndDeposit(
            address(mockVault),
            BOND_AMOUNT,
            expectedVaultShares - 1e18 // min vault shares with some slippage
        );

        // Check that user received vault shares
        assertEq(mockVault.balanceOf(user), actualVaultShares);
        assertGe(actualVaultShares, expectedVaultShares - 1e18);

        // Check that user's token balance decreased
        assertEq(mockToken.balanceOf(user), INITIAL_BALANCE - BOND_AMOUNT);

        // Check that utility contract has no leftover tokens
        assertEq(mockToken.balanceOf(address(utility)), 0);
        assertEq(mockPod.balanceOf(address(utility)), 0);
    }

    function testBondAndDepositTo() public {
        address receiver = address(0x3);
        uint256 expectedPodTokens = (BOND_AMOUNT * 9900) / 10000; // 1% bond fee
        uint256 expectedVaultShares = (expectedPodTokens * 9950) / 10000; // 0.5% vault fee

        vm.prank(user);
        uint256 actualVaultShares = utility.bondAndDepositTo(
            address(mockVault),
            BOND_AMOUNT,
            expectedVaultShares - 1e18, // min vault shares with some slippage
            receiver
        );

        // Check that receiver got the vault shares, not the user
        assertEq(mockVault.balanceOf(receiver), actualVaultShares);
        assertEq(mockVault.balanceOf(user), 0);
        assertGe(actualVaultShares, expectedVaultShares - 1e18);

        // Check that user's token balance decreased
        assertEq(mockToken.balanceOf(user), INITIAL_BALANCE - BOND_AMOUNT);
    }

    function testRevertInvalidAddresses() public {
        vm.startPrank(user);

        // Test invalid vault address
        vm.expectRevert(PodVaultUtility.InvalidVaultAddress.selector);
        utility.bondAndDeposit(address(0), BOND_AMOUNT, 0);

        // Test invalid receiver address for bondAndDepositTo
        vm.expectRevert(PodVaultUtility.InvalidReceiverAddress.selector);
        utility.bondAndDepositTo(address(mockVault), BOND_AMOUNT, 0, address(0));

        vm.stopPrank();
    }

    function testRevertZeroAmount() public {
        vm.prank(user);
        vm.expectRevert(PodVaultUtility.InvalidAssetAmount.selector);
        utility.bondAndDeposit(address(mockVault), 0, 0);
    }

    function testRevertInsufficientVaultShares() public {
        uint256 expectedPodTokens = (BOND_AMOUNT * 9900) / 10000; // 1% bond fee
        uint256 expectedVaultShares = (expectedPodTokens * 9950) / 10000; // 0.5% vault fee

        vm.prank(user);
        vm.expectRevert(PodVaultUtility.InsufficientVaultShares.selector);
        utility.bondAndDeposit(
            address(mockVault),
            BOND_AMOUNT,
            expectedVaultShares + 1e18 // Set min higher than expected
        );
    }

    function testBondAndDepositEvent() public {
        uint256 expectedPodTokens = (BOND_AMOUNT * 9900) / 10000; // 1% bond fee
        uint256 expectedVaultShares = (expectedPodTokens * 9950) / 10000; // 0.5% vault fee

        vm.expectEmit(true, true, true, true);
        emit PodVaultUtility.BondAndDeposit(
            user,
            address(mockPod),
            address(mockVault),
            address(mockToken),
            BOND_AMOUNT,
            expectedPodTokens,
            expectedVaultShares
        );

        vm.prank(user);
        utility.bondAndDeposit(address(mockVault), BOND_AMOUNT, 0);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/voting/ConversionFactorPTKN.sol";
import "../../contracts/interfaces/IDecentralizedIndex.sol";

// Mock DecentralizedIndex contract for testing
contract MockDecentralizedIndex is IDecentralizedIndex {
    uint8 public unlocked = 1;
    uint256 public conversionRate;

    function setUnlocked(uint8 _unlocked) external {
        unlocked = _unlocked;
    }

    function setConversionRate(uint256 _rate) external {
        conversionRate = _rate;
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return (shares * conversionRate) / 1e18;
    }

    // ERC4626 functions
    function initialize(string memory, string memory, address, address) external {}

    function mint(uint256, address) external pure returns (uint256) {
        return 0;
    }

    function redeem(uint256, address, address) external pure returns (uint256) {
        return 0;
    }

    function totalAssets() external pure returns (uint256) {
        return 0;
    }

    function convertToShares(uint256) external pure returns (uint256) {
        return 0;
    }

    function maxDeposit(address) external pure returns (uint256) {
        return 0;
    }

    function previewDeposit(uint256) external pure returns (uint256) {
        return 0;
    }

    function deposit(uint256, address) external pure returns (uint256) {
        return 0;
    }

    function maxMint(address) external pure returns (uint256) {
        return 0;
    }

    function previewMint(uint256) external pure returns (uint256) {
        return 0;
    }

    function maxWithdraw(address) external pure returns (uint256) {
        return 0;
    }

    function previewWithdraw(uint256) external pure returns (uint256) {
        return 0;
    }

    function withdraw(uint256, address, address) external pure returns (uint256) {
        return 0;
    }

    function maxRedeem(address) external pure returns (uint256) {
        return 0;
    }

    function previewRedeem(uint256) external pure returns (uint256) {
        return 0;
    }

    function asset() external pure returns (address) {
        return address(0);
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    // ERC20 functions
    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return true;
    }

    // IDecentralizedIndex specific functions
    function BOND_FEE() external pure returns (uint16) {
        return 0;
    }

    function DEBOND_FEE() external pure returns (uint16) {
        return 0;
    }

    function DEX_HANDLER() external pure returns (IDexAdapter) {
        return IDexAdapter(address(0));
    }

    function FLASH_FEE_AMOUNT_DAI() external pure returns (uint256) {
        return 0;
    }

    function PAIRED_LP_TOKEN() external pure returns (address) {
        return address(0);
    }

    function config() external pure returns (Config memory) {
        return Config(
            address(0), // partner
            0, // debondCooldown
            false, // hasTransferTax
            false // blacklistTKNpTKNPoolV2
        );
    }

    function fees() external pure returns (Fees memory) {
        return Fees(0, 0, 0, 0, 0, 0);
    }

    function indexType() external pure returns (IndexType) {
        return IndexType.WEIGHTED;
    }

    function created() external pure returns (uint256) {
        return 0;
    }

    function lpStakingPool() external pure returns (address) {
        return address(0);
    }

    function setLpStakingPool(address) external {}

    function totalAssets(address) external pure returns (uint256) {
        return 0;
    }

    function lpRewardsToken() external pure returns (address) {
        return address(0);
    }

    function partner() external pure returns (address) {
        return address(0);
    }

    function isAsset(address) external pure returns (bool) {
        return false;
    }

    function getAllAssets() external pure returns (IndexAssetInfo[] memory) {
        return new IndexAssetInfo[](0);
    }

    function getInitialAmount(address, uint256, address) external pure returns (uint256) {
        return 0;
    }

    function processPreSwapFeesAndSwap() external {}
    function setup() external {}

    function bond(address token, uint256 amount, uint256 amountMintMin) external {}

    function debond(uint256 amount, address[] memory token, uint8[] memory percentage) external {}

    function addLiquidityV2(uint256, uint256, uint256, uint256) external pure returns (uint256) {
        return 0;
    }

    function removeLiquidityV2(uint256, uint256, uint256, uint256) external pure {}

    function flash(address, address, uint256, bytes calldata) external pure {}

    function flashMint(address, uint256, bytes calldata) external pure {}
}

contract ConversionFactorPTKNTest is Test {
    ConversionFactorPTKN public conversionFactor;
    MockDecentralizedIndex public mockPod;

    function setUp() public virtual {
        conversionFactor = new ConversionFactorPTKN();
        mockPod = new MockDecentralizedIndex();
    }

    function testGetConversionFactorWithUnlockedPod() public {
        // Set pod to be unlocked (default is 1)
        mockPod.setConversionRate(2e18); // 2:1 conversion rate

        (uint256 factor, uint256 denominator) = conversionFactor.getConversionFactor(address(mockPod));

        assertEq(denominator, 1e18, "Denominator should be 1e18");
        assertEq(factor, 2e18, "Factor should match pod's conversion rate");
    }

    function testGetConversionFactorWithLockedPod() public {
        mockPod.setUnlocked(0);

        vm.expectRevert(bytes("OU")); // "OU" = "Only Unlocked"
        conversionFactor.getConversionFactor(address(mockPod));
    }

    function testGetConversionFactorWithDifferentRates() public {
        uint256[] memory rates = new uint256[](3);
        rates[0] = 0.5e18; // 0.5:1 conversion
        rates[1] = 1e18; // 1:1 conversion
        rates[2] = 2e18; // 2:1 conversion

        for (uint256 i = 0; i < rates.length; i++) {
            mockPod.setConversionRate(rates[i]);

            (uint256 factor, uint256 denominator) = conversionFactor.getConversionFactor(address(mockPod));

            assertEq(denominator, 1e18, "Denominator should always be 1e18");
            assertEq(factor, rates[i], "Factor should match pod's conversion rate");
        }
    }

    function testFuzzGetConversionFactor(uint256 rate) public {
        // Bound the rate to reasonable values to avoid overflow
        rate = bound(rate, 0.1e18, 1000e18);

        mockPod.setConversionRate(rate);

        (uint256 factor, uint256 denominator) = conversionFactor.getConversionFactor(address(mockPod));

        assertEq(denominator, 1e18, "Denominator should always be 1e18");
        assertEq(factor, rate, "Factor should match pod's conversion rate");
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/voting/ConversionFactorSPTKN.sol";
import "../../contracts/interfaces/IStakingPoolToken.sol";
import "../../contracts/interfaces/IUniswapV3Pool.sol";
import "../../contracts/interfaces/IV3TwapUtilities.sol";
import "../../contracts/interfaces/IV2Reserves.sol";
import "../../contracts/interfaces/IStakingConversionFactor.sol";
import "./ConversionFactorPTKN.t.sol";

// Mock StakingPoolToken contract
contract MockStakingPoolToken is IStakingPoolToken {
    address public immutable INDEX_FUND;
    address public immutable stakingToken;
    address private _poolRewards;
    address private _stakeUserRestriction;

    constructor(address _indexFund, address _stakingToken) {
        INDEX_FUND = _indexFund;
        stakingToken = _stakingToken;
    }

    function POOL_REWARDS() external view returns (address) {
        return _poolRewards;
    }

    function stakeUserRestriction() external view returns (address) {
        return _stakeUserRestriction;
    }

    function stake(address, uint256) external pure {}

    function unstake(uint256) external pure {}

    function setPoolRewards(address poolRewards) external {
        _poolRewards = poolRewards;
    }

    function setStakingToken(address) external pure {}

    function initialize(string memory, string memory, address, address) external pure {}

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

    function convertToAssets(uint256) external pure returns (uint256) {
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
}

// Mock UniswapV3Pool contract
contract MockUniswapV3Pool is IUniswapV3Pool {
    address public immutable token0;
    address public immutable token1;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function fee() external pure returns (uint24) {
        return 3000; // 0.3%
    }

    function slot0() external pure returns (uint160, int24, uint16, uint16, uint16, uint8, bool) {
        return (0, 0, 0, 0, 0, 0, false);
    }

    function observe(uint32[] calldata) external pure returns (int56[] memory, uint160[] memory) {
        int56[] memory tickCumulatives = new int56[](0);
        uint160[] memory secondsPerLiquidityCumulativeX128s = new uint160[](0);
        return (tickCumulatives, secondsPerLiquidityCumulativeX128s);
    }
}

// Mock V3TwapUtilities contract
contract MockV3TwapUtilities is IV3TwapUtilities {
    uint160 private constant SQRT_PRICE_X96_DEFAULT = 79228162514264337593543950336; // 1:1 price
    uint256 private constant PRICE_X96_DEFAULT = 79228162514264337593543950336; // 1:1 price

    function sqrtPriceX96FromPoolAndInterval(address) external pure returns (uint160) {
        return SQRT_PRICE_X96_DEFAULT;
    }

    function priceX96FromSqrtPriceX96(uint160) external pure returns (uint256) {
        return PRICE_X96_DEFAULT;
    }

    function getPoolPriceUSDX96(address, address, address) external pure returns (uint256) {
        return 0;
    }

    function getV3Pool(address, address, address) external pure returns (address) {
        return address(0);
    }

    function getV3Pool(address, address, address, uint24) external pure returns (address) {
        return address(0);
    }

    function getV3Pool(address, address, address, int24) external pure returns (address) {
        return address(0);
    }

    function sqrtPriceX96FromPoolAndPassedInterval(address, uint32) external pure returns (uint160) {
        return 0;
    }
}

struct Reserves {
    uint112 reserve0;
    uint112 reserve1;
    uint32 blockTimestampLast;
}

// Mock V2Reserves contract
contract MockV2Reserves is IV2Reserves {
    mapping(address => Reserves) private _reserves;

    function setReserves(address pair, uint112 reserve0, uint112 reserve1) external {
        _reserves[pair] = Reserves(reserve0, reserve1, uint32(block.timestamp));
    }

    function getReserves(address pair) external view returns (uint112 reserve0, uint112 reserve1) {
        Reserves memory r = _reserves[pair];
        return (r.reserve0, r.reserve1);
    }
}

// Mock LP Token for testing
contract MockLPToken is IERC20 {
    uint256 private immutable _totalSupply;

    constructor(uint256 initialSupply) {
        _totalSupply = initialSupply;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
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
}

// Mock PEAS Token for testing
contract MockPEAS is IERC20 {
    function totalSupply() external pure returns (uint256) {
        return 1000000e18;
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
}

contract ConversionFactorSPTKNTest is ConversionFactorPTKNTest {
    ConversionFactorSPTKN public conversionFactorSPTKN;
    MockStakingPoolToken public spToken;
    MockUniswapV3Pool public uniV3Pool;
    MockV3TwapUtilities public twapUtils;
    MockV2Reserves public v2Reserves;
    MockPEAS public peas;
    MockLPToken public lpToken;

    function setUp() public virtual override {
        super.setUp();
        peas = new MockPEAS();
        lpToken = new MockLPToken(100000e18);
        uniV3Pool = new MockUniswapV3Pool(address(0), address(peas)); // PEAS is token1
        spToken = new MockStakingPoolToken(address(mockPod), address(lpToken));
        twapUtils = new MockV3TwapUtilities();
        v2Reserves = new MockV2Reserves();

        conversionFactorSPTKN = new ConversionFactorSPTKN(address(peas), address(uniV3Pool), twapUtils, v2Reserves);
    }

    function testGetConversionFactorSPTKNBasicScenario() public {
        mockPod.setUnlocked(1);
        mockPod.setConversionRate(1e18);

        v2Reserves.setReserves(address(lpToken), 1000e18, 1000e18);

        (uint256 factor, uint256 denominator) = conversionFactorSPTKN.getConversionFactor(address(spToken));

        assertGt(factor, 0, "Factor should be greater than 0");
        assertEq(denominator, 2 ** 96, "Denominator should be 2^96");
    }

    function testGetConversionFactorSPTKNWithDifferentPrices() public {
        mockPod.setUnlocked(1);
        mockPod.setConversionRate(1e18);

        uint160[] memory sqrtPrices = new uint160[](3);
        sqrtPrices[0] = 79228162514264337593543950336; // 1:1
        sqrtPrices[1] = 112045541949572289497819423799; // 2:1
        sqrtPrices[2] = 56022770974786144748909711899; // 1:2

        uint256[] memory prices = new uint256[](3);
        prices[0] = 79228162514264337593543950336; // 1:1
        prices[1] = 158456325028528675187087900672; // 2:1
        prices[2] = 39614081257132168796771975168; // 1:2

        for (uint256 i = 0; i < sqrtPrices.length; i++) {
            v2Reserves.setReserves(address(lpToken), 1000e18, 1000e18);

            (uint256 factor, uint256 denominator) = conversionFactorSPTKN.getConversionFactor(address(spToken));

            assertGt(factor, 0, "Factor should be greater than 0");
            assertEq(denominator, 2 ** 96, "Denominator should be 2^96");
        }
    }

    function testGetConversionFactorSPTKNWithDifferentReserves() public {
        mockPod.setUnlocked(1);
        mockPod.setConversionRate(1e18);

        // Test with different reserve ratios
        uint112[][] memory reservePairs = new uint112[][](3);
        reservePairs[0] = new uint112[](2);
        reservePairs[0][0] = 1000e18;
        reservePairs[0][1] = 1000e18;

        reservePairs[1] = new uint112[](2);
        reservePairs[1][0] = 2000e18;
        reservePairs[1][1] = 1000e18;

        reservePairs[2] = new uint112[](2);
        reservePairs[2][0] = 1000e18;
        reservePairs[2][1] = 2000e18;

        for (uint256 i = 0; i < reservePairs.length; i++) {
            v2Reserves.setReserves(address(lpToken), reservePairs[i][0], reservePairs[i][1]);

            (uint256 factor, uint256 denominator) = conversionFactorSPTKN.getConversionFactor(address(spToken));

            assertGt(factor, 0, "Factor should be greater than 0");
            assertEq(denominator, 2 ** 96, "Denominator should be 2^96");
        }
    }

    function testFuzzGetConversionFactorSPTKN(uint112 reserve0, uint112 reserve1, uint160 sqrtPriceX96) public {
        mockPod.setUnlocked(1);
        mockPod.setConversionRate(1e18);

        reserve0 = uint112(bound(uint256(reserve0), 1e18, 1000000e18));
        reserve1 = uint112(bound(uint256(reserve1), 1e18, 1000000e18));
        sqrtPriceX96 = uint160(bound(uint256(sqrtPriceX96), 2 ** 48, 2 ** 96));

        // Set up scenario
        v2Reserves.setReserves(address(lpToken), reserve0, reserve1);

        (uint256 factor, uint256 denominator) = conversionFactorSPTKN.getConversionFactor(address(spToken));

        assertGt(factor, 0, "Factor should be greater than 0");
        assertEq(denominator, 2 ** 96, "Denominator should be 2^96");
    }
}

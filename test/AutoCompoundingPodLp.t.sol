// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../contracts/AutoCompoundingPodLp.sol";
import "../contracts/interfaces/IDecentralizedIndex.sol";
import "../contracts/interfaces/IDexAdapter.sol";
import "../contracts/interfaces/IFraxlendPair.sol";
import "../contracts/interfaces/IIndexUtils.sol";
import "../contracts/interfaces/IStakingPoolToken.sol";
import "../contracts/interfaces/ITokenRewards.sol";

contract AutoCompoundingPodLpTest is Test {
    AutoCompoundingPodLp public autoCompoundingPodLp;
    MockDecentralizedIndex public mockPod;
    MockDexAdapter public mockDexAdapter;
    MockIndexUtils public mockIndexUtils;
    MockStakingPoolToken public mockStakingPoolToken;
    MockTokenRewards public mockTokenRewards;
    MockERC20 public mockAsset;
    MockERC20 public rewardToken1;
    MockERC20 public rewardToken2;
    MockERC20 public rewardToken3;
    MockERC20 public pairedLpToken;
    address public owner;
    address public user;

    function setUp() public {
        owner = address(this);
        user = address(0x1);

        mockTokenRewards = new MockTokenRewards();
        mockStakingPoolToken = new MockStakingPoolToken();
        mockStakingPoolToken.setPoolRewards(address(mockTokenRewards));

        mockPod = new MockDecentralizedIndex();
        mockDexAdapter = new MockDexAdapter();
        mockIndexUtils = new MockIndexUtils();
        mockAsset = new MockERC20("Mock LP Token", "MLT");
        rewardToken1 = new MockERC20("Reward Token 1", "RT1");
        rewardToken2 = new MockERC20("Reward Token 2", "RT2");
        rewardToken3 = new MockERC20("Reward Token 3", "RT3");
        pairedLpToken = new MockERC20("Paired LP Token", "PLT");

        mockPod.setLpStakingPool(address(mockStakingPoolToken));
        mockPod.setPairedLpToken(address(pairedLpToken));
        mockPod.setLpRewardsToken(address(rewardToken3));

        autoCompoundingPodLp = new AutoCompoundingPodLp(
            "Auto Compounding Pod LP",
            "acPodLP",
            false,
            IDecentralizedIndex(address(mockPod)),
            IDexAdapter(address(mockDexAdapter)),
            IIndexUtils(address(mockIndexUtils))
        );
    }

    function testConvertToShares() public view {
        uint256 assets = 1000 * 1e18;
        uint256 shares = autoCompoundingPodLp.convertToShares(assets);
        assertEq(shares, assets);
    }

    function testConvertToAssets() public view {
        uint256 shares = 1000 * 1e18;
        uint256 assets = autoCompoundingPodLp.convertToAssets(shares);
        assertEq(assets, shares);
    }

    function testSetYieldConvEnabled() public {
        assertEq(autoCompoundingPodLp.yieldConvEnabled(), true);

        autoCompoundingPodLp.setYieldConvEnabled(false, false, 0, 0);
        assertEq(autoCompoundingPodLp.yieldConvEnabled(), false);

        autoCompoundingPodLp.setYieldConvEnabled(true, false, 0, 0);
        assertEq(autoCompoundingPodLp.yieldConvEnabled(), true);
    }

    function testSetProtocolFee() public {
        // Mock the necessary functions and set up the test scenario
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(rewardToken1);
        rewardTokens[1] = address(rewardToken2);

        mockTokenRewards.setProcessedRewardTokens(rewardTokens);

        assertEq(autoCompoundingPodLp.protocolFee(), 50);

        autoCompoundingPodLp.setProtocolFee(100, 0, block.timestamp);
        assertEq(autoCompoundingPodLp.protocolFee(), 100);

        vm.expectRevert(bytes("MAX"));
        autoCompoundingPodLp.setProtocolFee(1001, 0, block.timestamp);
    }

    function testProcessAllRewardsTokensToPodLp() public {
        // Mock the necessary functions and set up the test scenario
        address[] memory rewardTokens = new address[](2);
        rewardTokens[0] = address(rewardToken1);
        rewardTokens[1] = address(rewardToken2);

        mockTokenRewards.setProcessedRewardTokens(rewardTokens);

        uint256 lpAmountOut = 50 * 1e18;
        mockDexAdapter.setSwapV3SingleReturn(lpAmountOut);
        deal(autoCompoundingPodLp.pod().PAIRED_LP_TOKEN(), address(autoCompoundingPodLp), lpAmountOut);
        mockIndexUtils.setAddLPAndStakeReturn(lpAmountOut);

        // Set initial totalAssets
        uint256 initialTotalAssets = 1000 * 1e18;
        deal(address(autoCompoundingPodLp.asset()), address(this), initialTotalAssets);
        IERC20(autoCompoundingPodLp.asset()).approve(address(autoCompoundingPodLp), initialTotalAssets);
        autoCompoundingPodLp.deposit(initialTotalAssets, address(this));

        uint256 rewardAmount = 100 * 1e18;
        rewardToken1.mint(address(autoCompoundingPodLp), rewardAmount);
        rewardToken2.mint(address(autoCompoundingPodLp), rewardAmount);

        uint256 processedLp = autoCompoundingPodLp.processAllRewardsTokensToPodLp(0, block.timestamp);
        assertEq(processedLp, lpAmountOut * 2, "Processed LP amount mismatch");
        assertEq(autoCompoundingPodLp.totalAssets(), initialTotalAssets + lpAmountOut * 2, "Total assets mismatch");
    }
}

// Mock contracts for testing
contract MockDecentralizedIndex is ERC20, IDecentralizedIndex {
    address private _lpStakingPool;
    address private _pairedLpToken;
    address private _lpRewardsToken;

    constructor() ERC20("Test Pod", "ptPOD") {}

    function setup() external {}

    function setLpStakingPool(address newLpStakingPool) external {
        _lpStakingPool = newLpStakingPool;
    }

    function setPairedLpToken(address newPairedLpToken) external {
        _pairedLpToken = newPairedLpToken;
    }

    function setLpRewardsToken(address newLpRewardsToken) external {
        _lpRewardsToken = newLpRewardsToken;
    }

    function config() external view override returns (IDecentralizedIndex.Config memory _c) {}

    function fees() external view override returns (IDecentralizedIndex.Fees memory _f) {}

    function lpStakingPool() external view override returns (address) {
        return _lpStakingPool;
    }

    function PAIRED_LP_TOKEN() external view override returns (address) {
        return _pairedLpToken;
    }

    function lpRewardsToken() external view override returns (address) {
        return _lpRewardsToken;
    }

    function DEX_HANDLER() external pure override returns (IDexAdapter) {
        return IDexAdapter(address(0));
    }

    // Implement other required functions with default values
    function BOND_FEE() external pure override returns (uint16) {
        return 0;
    }

    function DEBOND_FEE() external pure override returns (uint16) {
        return 0;
    }

    function FLASH_FEE_AMOUNT_DAI() external pure override returns (uint256) {
        return 0;
    }

    function addLiquidityV2(uint256, uint256, uint256, uint256) external pure override returns (uint256) {
        return 0;
    }

    function totalAssets() external pure returns (uint256) {
        return 0;
    }

    function totalAssets(address) external pure returns (uint256) {
        return 0;
    }

    function convertToShares(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function convertToAssets(uint256 shares) external pure returns (uint256) {
        return shares;
    }

    function bond(address, uint256, uint256) external pure override {}

    function created() external pure override returns (uint256) {
        return 0;
    }

    function debond(uint256, address[] memory, uint8[] memory) external pure override {}
    function flash(address, address, uint256, bytes calldata) external pure override {}
    function flashMint(address, uint256, bytes calldata) external pure override {}

    function getAllAssets() external pure override returns (IndexAssetInfo[] memory) {
        return new IndexAssetInfo[](0);
    }

    function getInitialAmount(address, uint256, address) external pure override returns (uint256) {
        return 0;
    }

    function indexType() external pure override returns (IDecentralizedIndex.IndexType) {
        return IDecentralizedIndex.IndexType.WEIGHTED;
    }

    function isAsset(address) external pure override returns (bool) {
        return false;
    }

    function partner() external pure override returns (address) {
        return address(0);
    }

    function processPreSwapFeesAndSwap() external pure override {}
    function removeLiquidityV2(uint256, uint256, uint256, uint256) external pure override {}

    function unlocked() external pure override returns (uint8) {
        return 0;
    }
}

contract MockDexAdapter is IDexAdapter, Test {
    uint256 private _swapV3SingleReturn;
    mapping(address => mapping(address => uint256)) private _swapV2SingleReturns;

    function setSwapV3SingleReturn(uint256 amount) external {
        _swapV3SingleReturn = amount;
    }

    function setSwapV2SingleReturn(address tokenIn, address tokenOut, uint256 amount) external {
        _swapV2SingleReturns[tokenIn][tokenOut] = amount;
    }

    function swapV3Single(address, address, uint24, uint256, uint256, address)
        external
        view
        override
        returns (uint256)
    {
        return _swapV3SingleReturn;
    }

    function swapV2Single(address tokenIn, address tokenOut, uint256 amountIn, uint256, address recipient)
        external
        override
        returns (uint256)
    {
        uint256 amountOut = _swapV2SingleReturns[tokenIn][tokenOut];
        if (amountOut == 0) {
            amountOut = amountIn; // Default 1:1 swap if not set
        }
        deal(tokenIn, msg.sender, IERC20(tokenIn).balanceOf(msg.sender) - amountIn);
        deal(tokenOut, recipient, amountOut);
        return amountOut;
    }

    function getV3Pool(address, address, uint24) external pure override returns (address) {
        return address(0x7);
    }

    function getV3Pool(address, address, int24) external pure override returns (address) {
        return address(0x7);
    }

    function getReserves(address) external pure override returns (uint112, uint112) {
        return (uint112(0), uint112(0));
    }

    // Implement other required functions with default values
    function ASYNC_INITIALIZE() external pure returns (bool) {
        return false;
    }

    function V2_ROUTER() external pure returns (address) {
        return address(0);
    }

    function V3_ROUTER() external pure returns (address) {
        return address(0);
    }

    function WETH() external pure returns (address) {
        return address(0);
    }

    function addLiquidity(address, address, uint256, uint256, uint256, uint256, address, uint256) external pure {}

    function createV2Pool(address, address) external pure returns (address) {
        return address(0);
    }

    function getV2Pool(address, address) external pure returns (address) {
        return address(0);
    }

    function removeLiquidity(address, address, uint256, uint256, uint256, address, uint256) external pure {}

    function swapV2SingleExactOut(address, address, uint256, uint256, address) external pure returns (uint256) {
        return 0;
    }
}

contract MockIndexUtils is IIndexUtils {
    uint256 private _addLPAndStakeReturn;

    function setAddLPAndStakeReturn(uint256 amount) external {
        _addLPAndStakeReturn = amount;
    }

    function addLPAndStake(IDecentralizedIndex, uint256, address, uint256, uint256, uint256, uint256)
        external
        payable
        override
        returns (uint256)
    {
        return _addLPAndStakeReturn;
    }

    // Implement other required functions with default values
    function unstakeAndRemoveLP(IDecentralizedIndex, uint256, uint256, uint256, uint256) external pure {}
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockStakingPoolToken is ERC20, IStakingPoolToken {
    address private _stakingPoolToken;
    address private _poolRewards;
    uint256 private constant _CONVERSION_FACTOR = 1e18;
    uint256 private constant _REWARDS_DURATION = 7 days;
    address private constant _REWARDS_TOKEN = address(0);
    address private constant _STAKING_TOKEN = address(0);

    constructor() ERC20("Mock Staking Pool Token", "MSPT") {}

    function setPoolRewards(address newPoolRewards) external override {
        _poolRewards = newPoolRewards;
    }

    function setStakingToken(address __stakingToken) external override {
        _stakingPoolToken = __stakingToken;
    }

    function INDEX_FUND() external pure override returns (address) {
        return address(0);
    }

    function POOL_REWARDS() external view override returns (address) {
        return _poolRewards;
    }

    function stakingToken() external pure override returns (address) {
        return address(0);
    }

    function stakeUserRestriction() external pure override returns (address) {
        return address(0);
    }

    function stake(address user, uint256 amount) external override {
        _mint(user, amount);
    }

    function unstake(uint256 amount) external override {
        _burn(msg.sender, amount);
    }
}

contract MockTokenRewards is ITokenRewards {
    address[] private _processedRewardTokens;

    function setProcessedRewardTokens(address[] memory tokens) external {
        _processedRewardTokens = tokens;
    }

    function getProcessedRewardTokens() external view returns (address[] memory) {
        return _processedRewardTokens;
    }

    function totalShares() external pure returns (uint256) {
        return 0;
    }

    function totalStakers() external pure returns (uint256) {
        return 0;
    }

    function rewardsToken() external pure returns (address) {
        return address(0);
    }

    function trackingToken() external pure returns (address) {
        return address(0);
    }

    function depositFromPairedLpToken(uint256 amount) external {}

    function depositRewards(address token, uint256 amount) external {}

    function depositRewardsNoTransfer(address token, uint256 amount) external {}

    function claimReward(address wallet) external {}

    function getAllRewardsTokens() external view returns (address[] memory) {
        return _processedRewardTokens;
    }

    function setShares(address wallet, uint256 amount, bool sharesRemoving) external {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import 'forge-std/Test.sol';
import '../contracts/AutoCompoundingPodLp.sol';
import '../contracts/interfaces/IDecentralizedIndex.sol';
import '../contracts/interfaces/IDexAdapter.sol';
import '../contracts/interfaces/IIndexUtils.sol';
import '../contracts/interfaces/IRewardsWhitelister.sol';
import '../contracts/interfaces/IV3TwapUtilities.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract AutoCompoundingPodLpTest is Test {
  AutoCompoundingPodLp public autoCompoundingPodLp;
  MockDecentralizedIndex public mockPod;
  MockDexAdapter public mockDexAdapter;
  MockIndexUtils public mockIndexUtils;
  MockRewardsWhitelister public mockRewardsWhitelister;
  MockV3TwapUtilities public mockV3TwapUtilities;
  MockERC20 public mockAsset;
  address public owner;
  address public user;

  function setUp() public {
    owner = address(this);
    user = address(0x1);

    mockPod = new MockDecentralizedIndex();
    mockDexAdapter = new MockDexAdapter();
    mockIndexUtils = new MockIndexUtils();
    mockRewardsWhitelister = new MockRewardsWhitelister();
    mockV3TwapUtilities = new MockV3TwapUtilities();
    mockAsset = new MockERC20('Mock LP Token', 'MLT');

    autoCompoundingPodLp = new AutoCompoundingPodLp(
      'Auto Compounding Pod LP',
      'acPodLP',
      IDecentralizedIndex(address(mockPod)),
      IDexAdapter(address(mockDexAdapter)),
      IIndexUtils(address(mockIndexUtils)),
      IRewardsWhitelister(address(mockRewardsWhitelister)),
      IV3TwapUtilities(address(mockV3TwapUtilities))
    );

    mockPod.setLpStakingPool(address(mockAsset));
  }

  function testInitialState() public view {
    assertEq(autoCompoundingPodLp.name(), 'Auto Compounding Pod LP');
    assertEq(autoCompoundingPodLp.symbol(), 'acPodLP');
    assertEq(address(autoCompoundingPodLp.pod()), address(mockPod));
    assertEq(autoCompoundingPodLp.yieldConvEnabled(), true);
    assertEq(autoCompoundingPodLp.protocolFee(), 50);
  }

  function testDeposit() public {
    uint256 depositAmount = 1000 * 1e18;
    deal(address(mockAsset), user, depositAmount);

    vm.startPrank(user);
    mockAsset.approve(address(autoCompoundingPodLp), depositAmount);
    uint256 shares = autoCompoundingPodLp.deposit(depositAmount, user);
    vm.stopPrank();

    assertEq(autoCompoundingPodLp.balanceOf(user), shares);
    assertEq(autoCompoundingPodLp.totalAssets(), depositAmount);
  }

  function testWithdraw() public {
    uint256 depositAmount = 1000 * 1e18;
    deal(address(mockAsset), user, depositAmount);

    vm.startPrank(user);
    mockAsset.approve(address(autoCompoundingPodLp), depositAmount);
    uint256 shares = autoCompoundingPodLp.deposit(depositAmount, user);

    uint256 withdrawAmount = 500 * 1e18;
    uint256 withdrawShares = autoCompoundingPodLp.convertToShares(
      withdrawAmount
    );
    autoCompoundingPodLp.withdraw(withdrawAmount, user, user);
    vm.stopPrank();

    assertEq(autoCompoundingPodLp.balanceOf(user), shares - withdrawShares);
    assertEq(
      autoCompoundingPodLp.totalAssets(),
      depositAmount - withdrawAmount
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

    autoCompoundingPodLp.setYieldConvEnabled(false);
    assertEq(autoCompoundingPodLp.yieldConvEnabled(), false);

    autoCompoundingPodLp.setYieldConvEnabled(true);
    assertEq(autoCompoundingPodLp.yieldConvEnabled(), true);
  }

  function testSetProtocolFee() public {
    assertEq(autoCompoundingPodLp.protocolFee(), 50);

    autoCompoundingPodLp.setProtocolFee(100);
    assertEq(autoCompoundingPodLp.protocolFee(), 100);

    vm.expectRevert(bytes('MAX'));
    autoCompoundingPodLp.setProtocolFee(1001);
  }

  // TODO: update and resolve
  // function testProcessAllRewardsTokensToPodLp() public {
  //   // Mock the necessary functions and set up the test scenario
  //   address[] memory rewardTokens = new address[](2);
  //   rewardTokens[0] = address(0x2);
  //   rewardTokens[1] = address(0x3);

  //   mockRewardsWhitelister.setFullWhitelist(rewardTokens);

  //   uint256 rewardAmount = 100 * 1e18;
  //   deal(rewardTokens[0], address(autoCompoundingPodLp), rewardAmount);
  //   deal(rewardTokens[1], address(autoCompoundingPodLp), rewardAmount);

  //   uint256 lpAmountOut = 50 * 1e18;
  //   mockDexAdapter.setSwapV3SingleReturn(lpAmountOut);
  //   mockIndexUtils.setAddLPAndStakeReturn(lpAmountOut);

  //   uint256 initialTotalAssets = autoCompoundingPodLp.totalAssets();
  //   uint256 processedLp = autoCompoundingPodLp.processAllRewardsTokensToPodLp(
  //     0,
  //     block.timestamp
  //   );

  //   assertEq(processedLp, lpAmountOut * 2);
  //   assertEq(
  //     autoCompoundingPodLp.totalAssets(),
  //     initialTotalAssets + lpAmountOut * 2
  //   );
  // }
}

// Mock contracts for testing
contract MockDecentralizedIndex is IDecentralizedIndex {
  address private _lpStakingPool;
  address private constant PAIRED_LP_TOKEN_ADDRESS = address(0x5);
  address private constant LP_REWARDS_TOKEN_ADDRESS = address(0x6);

  function setLpStakingPool(address newLpStakingPool) external {
    _lpStakingPool = newLpStakingPool;
  }

  function lpStakingPool() external view override returns (address) {
    return _lpStakingPool;
  }

  function PAIRED_LP_TOKEN() external pure override returns (address) {
    return PAIRED_LP_TOKEN_ADDRESS;
  }

  function lpRewardsToken() external pure override returns (address) {
    return LP_REWARDS_TOKEN_ADDRESS;
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
  function addLiquidityV2(
    uint256,
    uint256,
    uint256,
    uint256
  ) external pure override returns (uint256) {
    return 0;
  }
  function allowance(
    address,
    address
  ) external pure override returns (uint256) {
    return 0;
  }
  function approve(address, uint256) external pure override returns (bool) {
    return false;
  }
  function balanceOf(address) external pure override returns (uint256) {
    return 0;
  }
  function totalAssets() external view returns (uint256 totalManagedAssets) {}
  function convertToShares(
    uint256 assets
  ) external view returns (uint256 shares) {}
  function convertToAssets(
    uint256 shares
  ) external view returns (uint256 assets) {}
  function bond(
    address token,
    uint256 amount,
    uint256 amountMintMin
  ) external pure override {}
  function created() external pure override returns (uint256) {
    return 0;
  }
  function debond(
    uint256 amount,
    address[] memory token,
    uint8[] memory percentage
  ) external pure override {}
  function flash(
    address recipient,
    address token,
    uint256 amount,
    bytes calldata data
  ) external pure override {}
  function getAllAssets()
    external
    pure
    override
    returns (IndexAssetInfo[] memory)
  {
    return new IndexAssetInfo[](0);
  }
  function getIdxPriceUSDX96()
    external
    pure
    override
    returns (uint256, uint256)
  {
    return (0, 0);
  }
  function getInitialAmount(
    address,
    uint256,
    address
  ) external pure override returns (uint256) {
    return 0;
  }
  function getTokenPriceUSDX96(
    address
  ) external pure override returns (uint256) {
    return 0;
  }
  function indexType()
    external
    pure
    override
    returns (IDecentralizedIndex.IndexType)
  {
    return IDecentralizedIndex.IndexType.WEIGHTED;
  }
  function isAsset(address) external pure override returns (bool) {
    return false;
  }
  function partner() external pure override returns (address) {
    return address(0);
  }
  function processPreSwapFeesAndSwap() external pure override {}
  function removeLiquidityV2(
    uint256 liquidity,
    uint256 amountTokenMin,
    uint256 amountPairedTokenMin,
    uint256 deadline
  ) external pure override {}
  function totalSupply() external pure override returns (uint256) {
    return 0;
  }
  function transfer(address, uint256) external pure override returns (bool) {
    return false;
  }
  function transferFrom(
    address,
    address,
    uint256
  ) external pure override returns (bool) {
    return false;
  }
  function unlocked() external pure override returns (uint8) {
    return 0;
  }
}

contract MockDexAdapter is IDexAdapter {
  uint256 private _swapV3SingleReturn;

  function setSwapV3SingleReturn(uint256 amount) external {
    _swapV3SingleReturn = amount;
  }

  function swapV3Single(
    address,
    address,
    uint24,
    uint256,
    uint256,
    address
  ) external view override returns (uint256) {
    return _swapV3SingleReturn;
  }

  function swapV2Single(
    address,
    address,
    uint256,
    uint256,
    address
  ) external pure override returns (uint256) {
    return 100 * 1e18;
  }

  function getV3Pool(
    address,
    address,
    uint24
  ) external pure override returns (address) {
    return address(0x7);
  }
  function getV3Pool(
    address,
    address,
    int24
  ) external pure override returns (address) {
    return address(0x7);
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
  function addLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  ) external {}
  function createV2Pool(address, address) external pure returns (address) {
    return address(0);
  }
  function extraRewardsHook(
    address _token0,
    address _token1
  ) external returns (address[] memory tokens, uint256[] memory amounts) {}
  function getV2Pool(address, address) external pure returns (address pool) {
    return address(0);
  }
  function removeLiquidity(
    address tokenA,
    address tokenB,
    uint256 liquidity,
    uint256 amountAMin,
    uint256 amountBMin,
    address to,
    uint256 deadline
  ) external pure {}
  function swapV2SingleExactOut(
    address,
    address,
    uint256,
    uint256,
    address
  ) external pure returns (uint256) {
    return 0;
  }
}

contract MockIndexUtils is IIndexUtils {
  uint256 private _addLPAndStakeReturn;

  function setAddLPAndStakeReturn(uint256 amount) external {
    _addLPAndStakeReturn = amount;
  }

  function addLPAndStake(
    IDecentralizedIndex,
    uint256,
    address,
    uint256,
    uint256,
    uint256,
    uint256
  ) external payable override returns (uint256) {
    return _addLPAndStakeReturn;
  }

  // Implement other required functions with default values
  function unstakeAndRemoveLP(
    IDecentralizedIndex idx,
    uint256 liquidity,
    uint256 amountTokenMin,
    uint256 amountPairedTokenMin,
    uint256 deadline
  ) external pure {}
}

contract MockRewardsWhitelister is IRewardsWhitelister {
  address[] private _fullWhitelist;

  function setFullWhitelist(address[] memory wl) external {
    _fullWhitelist = wl;
  }

  function getFullWhitelist()
    external
    view
    override
    returns (address[] memory)
  {
    return _fullWhitelist;
  }

  function whitelist(address) external pure returns (bool) {
    return false;
  }
}

contract MockV3TwapUtilities is IV3TwapUtilities {
  function sqrtPriceX96FromPoolAndInterval(
    address
  ) external pure override returns (uint160) {
    return 1000000;
  }

  function priceX96FromSqrtPriceX96(
    uint160
  ) external pure override returns (uint256) {
    return 1000000;
  }

  // Implement other required functions with default values
  function getPoolPriceUSDX96(
    address,
    address,
    address
  ) external pure returns (uint256) {
    return 0;
  }
  function getV3Pool(
    address,
    address,
    address
  ) external pure returns (address pool) {
    return address(0);
  }
  function getV3Pool(
    address,
    address,
    address,
    uint24
  ) external pure returns (address pool) {
    return address(0);
  }
  function getV3Pool(
    address,
    address,
    address,
    int24
  ) external pure returns (address pool) {
    return address(0);
  }
  function sqrtPriceX96FromPoolAndPassedInterval(
    address,
    uint32
  ) external pure returns (uint160 sqrtPriceX96) {
    return 0;
  }
}

contract MockERC20 is ERC20 {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}

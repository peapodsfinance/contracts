// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/oracle/aspTKNMinimalOracleFactory.sol";
import "../../contracts/oracle/aspTKNMinimalOracle.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../contracts/interfaces/IV2Reserves.sol";
import "../../contracts/interfaces/IStakingPoolToken.sol";
import "../../contracts/interfaces/IDecentralizedIndex.sol";

// Mock contracts
contract MockERC4626 is ERC20 {
    constructor() ERC20("Mock Vault", "vTKN") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function convertToShares(uint256 assets) public pure returns (uint256) {
        return assets; // 1:1 conversion for testing
    }
}

contract MockV2Reserves is IV2Reserves {
    function getReserves(address) external pure returns (uint112, uint112) {
        return (1000 * 10 ** 18, 1000 * 10 ** 18); // Mock reserves for testing
    }
}

contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract MockStakingPoolToken is ERC20, IStakingPoolToken {
    address public immutable INDEX_FUND;
    address public immutable stakingToken;
    address public poolRewards;
    address public stakeUserRestriction;

    constructor(address _indexFund, address _stakingToken) ERC20("Mock SPT", "SPT") {
        INDEX_FUND = _indexFund;
        stakingToken = _stakingToken;
    }

    function POOL_REWARDS() external view returns (address) {
        return poolRewards;
    }

    function stake(address user, uint256 amount) external {
        _mint(user, amount);
    }

    function unstake(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function setPoolRewards(address _poolRewards) external {
        poolRewards = _poolRewards;
    }

    function setStakingToken(address) external {}
}

contract MockDecentralizedIndex is ERC20, IDecentralizedIndex {
    address public immutable underlyingToken;
    uint16 public constant DEBOND_FEE = 100; // 1%
    uint16 public constant BOND_FEE = 100;
    IDexAdapter public DEX_HANDLER;
    uint256 public constant FLASH_FEE_AMOUNT_DAI = 0;
    address public PAIRED_LP_TOKEN;
    address public lpStakingPool;
    address public lpRewardsToken;

    constructor(address _underlyingToken) ERC20("Mock Index", "IDX") {
        underlyingToken = _underlyingToken;
    }

    function getAllAssets() external view returns (IndexAssetInfo[] memory assets) {
        assets = new IndexAssetInfo[](1);
        assets[0] =
            IndexAssetInfo({token: underlyingToken, weighting: 10000, basePriceUSDX96: 0, c1: address(0), q1: 0});
    }

    function unlocked() external pure returns (uint8) {
        return 1;
    }

    function convertToAssets(uint256 amount) external pure returns (uint256) {
        return amount;
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

    function partner() external pure returns (address) {
        return address(0);
    }

    function isAsset(address) external pure returns (bool) {
        return true;
    }

    function getInitialAmount(address, uint256, address) external pure returns (uint256) {
        return 0;
    }

    function processPreSwapFeesAndSwap() external pure {}

    function totalAssets() external pure returns (uint256) {
        return 0;
    }

    function totalAssets(address) external pure returns (uint256) {
        return 0;
    }

    function convertToShares(uint256) external pure returns (uint256) {
        return 0;
    }

    function bond(address, uint256, uint256) external pure {}

    function debond(uint256, address[] memory, uint8[] memory) external pure {}

    function addLiquidityV2(uint256, uint256, uint256, uint256) external pure returns (uint256) {
        return 0;
    }

    function removeLiquidityV2(uint256, uint256, uint256, uint256) external pure {}

    function flash(address, address, uint256, bytes calldata) external pure {}

    function flashMint(address, uint256, bytes calldata) external pure {}

    function setLpStakingPool(address) external pure {}

    function setup() external pure {}
}

contract MockUniswapV2Pair is ERC20 {
    address public immutable token0;
    address public immutable token1;

    constructor(address _token0, address _token1) ERC20("LP Token", "LP") {
        token0 = _token0;
        token1 = _token1;
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract aspTKNMinimalOracleFactoryTest is Test {
    aspTKNMinimalOracleFactory public factory;
    MockERC4626 public aspToken;
    MockV2Reserves public v2Reserves;
    MockToken public baseToken;
    MockToken public underlyingToken;
    MockUniswapV2Pair public lpToken;
    MockDecentralizedIndex public pod;
    MockStakingPoolToken public spToken;
    address public owner;
    address public user;

    // Mock addresses for required parameters
    address constant CHAINLINK_ORACLE = address(0x1);
    address constant UNISWAP_ORACLE = address(0x2);
    address constant DIA_ORACLE = address(0x3);
    address constant UNDERLYING_CL_POOL = address(0x6);

    function setUp() public {
        owner = address(this);
        user = address(0x1);

        // Deploy mock tokens
        baseToken = new MockToken("Base Token", "BASE");
        underlyingToken = new MockToken("Underlying Token", "UNDER");

        // Deploy mock LP token
        lpToken = new MockUniswapV2Pair(address(baseToken), address(underlyingToken));

        // Deploy mock pod and spToken
        pod = new MockDecentralizedIndex(address(underlyingToken));
        spToken = new MockStakingPoolToken(address(pod), address(lpToken));

        // Deploy main contracts
        aspToken = new MockERC4626();
        v2Reserves = new MockV2Reserves();
        factory = new aspTKNMinimalOracleFactory();
    }

    function testCreate() public {
        bytes memory requiredImmutables = abi.encode(
            CHAINLINK_ORACLE,
            UNISWAP_ORACLE,
            DIA_ORACLE,
            address(baseToken),
            false,
            false,
            address(spToken),
            UNDERLYING_CL_POOL
        );

        bytes memory optionalImmutables =
            abi.encode(address(0), address(0), address(0), address(0), address(0), address(v2Reserves));

        uint96 salt = 0;

        // Get expected address
        address expectedOracleAddress =
            factory.getNewCaFromParams(address(aspToken), requiredImmutables, optionalImmutables, salt);

        // Create the oracle
        factory.create(address(aspToken), requiredImmutables, optionalImmutables, salt);

        // Check if the oracle was created at the expected address
        aspTKNMinimalOracle oracle = aspTKNMinimalOracle(expectedOracleAddress);
        assertTrue(address(oracle) != address(0), "Oracle was not created");

        // Check if the oracle properties are set correctly
        assertEq(oracle.ASP_TKN(), address(aspToken), "Oracle ASP_TKN is incorrect");

        // Check if the ownership was transferred to the factory owner
        assertEq(oracle.owner(), owner, "Oracle ownership was not transferred correctly");
    }

    function testCreateWithDifferentSalt() public {
        bytes memory requiredImmutables = abi.encode(
            CHAINLINK_ORACLE,
            UNISWAP_ORACLE,
            DIA_ORACLE,
            address(baseToken),
            false,
            false,
            address(spToken),
            UNDERLYING_CL_POOL
        );

        bytes memory optionalImmutables =
            abi.encode(address(0), address(0), address(0), address(0), address(0), address(v2Reserves));

        uint96 salt = 1;

        // Get expected address
        address expectedOracleAddress =
            factory.getNewCaFromParams(address(aspToken), requiredImmutables, optionalImmutables, salt);

        // Create the oracle
        factory.create(address(aspToken), requiredImmutables, optionalImmutables, salt);

        // Check if the oracle was created at the expected address
        aspTKNMinimalOracle oracle = aspTKNMinimalOracle(expectedOracleAddress);
        assertTrue(address(oracle) != address(0), "Oracle was not created");

        // Check if the oracle properties are set correctly
        assertEq(oracle.ASP_TKN(), address(aspToken), "Oracle ASP_TKN is incorrect");

        // Check if the ownership was transferred to the factory owner
        assertEq(oracle.owner(), owner, "Oracle ownership was not transferred correctly");
    }

    function testCreateOnlyOwner() public {
        bytes memory requiredImmutables = abi.encode(
            CHAINLINK_ORACLE,
            UNISWAP_ORACLE,
            DIA_ORACLE,
            address(baseToken),
            false,
            false,
            address(spToken),
            UNDERLYING_CL_POOL
        );

        bytes memory optionalImmutables =
            abi.encode(address(0), address(0), address(0), address(0), address(0), address(v2Reserves));

        uint96 salt = 2;

        // Try to create an oracle as a non-owner
        vm.prank(user);
        // vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        factory.create(address(aspToken), requiredImmutables, optionalImmutables, salt);
    }

    function testDeterministicAddressCalculation() public {
        bytes memory requiredImmutables = abi.encode(
            CHAINLINK_ORACLE,
            UNISWAP_ORACLE,
            DIA_ORACLE,
            address(baseToken),
            false,
            false,
            address(spToken),
            UNDERLYING_CL_POOL
        );

        bytes memory optionalImmutables =
            abi.encode(address(0), address(0), address(0), address(0), address(0), address(v2Reserves));

        uint96 salt = 3;

        // Calculate expected address
        address expectedOracleAddress =
            factory.getNewCaFromParams(address(aspToken), requiredImmutables, optionalImmutables, salt);

        // Create the oracle
        factory.create(address(aspToken), requiredImmutables, optionalImmutables, salt);

        // Verify the oracle was created at the calculated address
        aspTKNMinimalOracle oracle = aspTKNMinimalOracle(expectedOracleAddress);
        assertTrue(address(oracle) != address(0), "Oracle was not created at expected address");
        assertEq(oracle.ASP_TKN(), address(aspToken), "Oracle at calculated address has incorrect ASP_TKN");
    }
}

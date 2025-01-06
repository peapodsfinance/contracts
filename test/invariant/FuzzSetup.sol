// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

// fuzzlib
import {FuzzBase} from "fuzzlib/FuzzBase.sol";

// forge
import {Test} from "forge-std/Test.sol";

// PEAS
import {PEAS} from "../../contracts/PEAS.sol";
import {V3TwapUtilities} from "../../contracts/twaputils/V3TwapUtilities.sol";
import {UniswapDexAdapter} from "../../contracts/dex/UniswapDexAdapter.sol";
import {IDecentralizedIndex} from "../../contracts/interfaces/IDecentralizedIndex.sol";
import {WeightedIndex} from "../../contracts/WeightedIndex.sol";
import {StakingPoolToken} from "../../contracts/StakingPoolToken.sol";
import {LendingAssetVault} from "../../contracts/LendingAssetVault.sol";
import {IndexUtils} from "../../contracts/IndexUtils.sol";
import {IIndexUtils} from "../../contracts/interfaces/IIndexUtils.sol";
import {MockIndexUtils} from "./mocks/MockIndexUtils.sol";
import {RewardsWhitelist} from "../../contracts/RewardsWhitelist.sol";
import {TokenRewards} from "../../contracts/TokenRewards.sol";

// oracles
import {ChainlinkSinglePriceOracle} from "../../contracts/oracle/ChainlinkSinglePriceOracle.sol";
import {UniswapV3SinglePriceOracle} from "../../contracts/oracle/UniswapV3SinglePriceOracle.sol";
import {DIAOracleV2SinglePriceOracle} from "../../contracts/oracle/DIAOracleV2SinglePriceOracle.sol";
import {V2ReservesUniswap} from "../../contracts/oracle/V2ReservesUniswap.sol";
import {aspTKNMinimalOracle} from "../../contracts/oracle/aspTKNMinimalOracle.sol";

// protocol fees
import {ProtocolFees} from "../../contracts/ProtocolFees.sol";
import {ProtocolFeeRouter} from "../../contracts/ProtocolFeeRouter.sol";

// autocompounding
import {AutoCompoundingPodLpFactory} from "../../contracts/AutoCompoundingPodLpFactory.sol";
import {AutoCompoundingPodLp} from "../../contracts/AutoCompoundingPodLp.sol";

// lvf
import {LeverageManager} from "../../contracts/lvf/LeverageManager.sol";

// fraxlend
import {FraxlendPairDeployer, ConstructorParams} from "./modules/fraxlend/FraxlendPairDeployer.sol";
import {FraxlendWhitelist} from "./modules/fraxlend/FraxlendWhitelist.sol";
import {FraxlendPairRegistry} from "./modules/fraxlend/FraxlendPairRegistry.sol";
import {FraxlendPair} from "./modules/fraxlend/FraxlendPair.sol";
import {VariableInterestRate} from "./modules/fraxlend/VariableInterestRate.sol";
import {IERC4626Extended} from "./modules/fraxlend/interfaces/IERC4626Extended.sol";

// flash
import {IVault} from "./modules/balancer/interfaces/IVault.sol";
import {BalancerFlashSource} from "../../contracts/flash/BalancerFlashSource.sol";
import {PodFlashSource} from "../../contracts/flash/PodFlashSource.sol";
import {UniswapV3FlashSource} from "../../contracts/flash/UniswapV3FlashSource.sol";

// uniswap-v2-core
import {UniswapV2Factory} from "v2-core/UniswapV2Factory.sol";
import {UniswapV2Pair} from "v2-core/UniswapV2Pair.sol";

// uniswap-v2-periphery
import {UniswapV2Router02} from "v2-periphery/UniswapV2Router02.sol";

// uniswap-v3-core
import {UniswapV3Factory} from "v3-core/UniswapV3Factory.sol";
import {UniswapV3Pool} from "v3-core/UniswapV3Pool.sol";

// uniswap-v3-periphery
import {SwapRouter02} from "swap-router/SwapRouter02.sol";
import {LiquidityManagement} from "v3-periphery/base/LiquidityManagement.sol";
import {PeripheryPayments} from "v3-periphery/base/PeripheryPayments.sol";
import {PoolAddress} from "v3-periphery/libraries/PoolAddress.sol";

// mocks
import {WETH9} from "./mocks/WETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {TestERC20} from "./mocks/TestERC20.sol";
import {TestERC4626Vault} from "./mocks/TestERC4626Vault.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";
import {MockUniV3Minter} from "./mocks/MockUniV3Minter.sol";
import {MockV3TwapUtilities} from "./mocks/MockV3TwapUtilities.sol";

import {PodHelperTest} from "../helpers/PodHelper.t.sol";

// bytecode for etching with forge (echidna configures this in echidna.yaml)
import {Bytecode} from "./helpers/Bytecode.sol";

contract FuzzSetup is PodHelperTest, FuzzBase {
    /*///////////////////////////////////////////////////////////////
                            GLOBAL VARIABLES
    ///////////////////////////////////////////////////////////////*/

    // external actors
    address internal user0 = vm.addr(uint256(keccak256("User0")));
    address internal user1 = vm.addr(uint256(keccak256("User1")));
    address internal user2 = vm.addr(uint256(keccak256("User2")));

    address[] internal users = [user0, user1, user2];
    uint256[] internal _fraxPercentages = [10000, 2500, 7500, 5000];

    // fraxlend protocol actors
    address internal comptroller = vm.addr(uint256(keccak256("comptroller")));
    address internal circuitBreaker = vm.addr(uint256(keccak256("circuitBreaker")));
    address internal timelock = vm.addr(uint256(keccak256("comptroller")));

    uint16 internal fee = 100;
    uint256 internal PRECISION = 10 ** 27;

    uint256 donatedAmount;
    uint256 lavDeposits;

    uint256 internal _peasPrice;
    uint256 internal _daiPrice;
    uint256 internal _wethPrice;
    uint256 internal _tokenAPrice;
    uint256 internal _tokenBPrice;
    uint256 internal _tokenCPrice;

    /*///////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    ///////////////////////////////////////////////////////////////*/

    PEAS internal _peas;
    MockV3TwapUtilities internal _twapUtils;
    UniswapDexAdapter internal _dexAdapter;
    LendingAssetVault internal _lendingAssetVault;
    RewardsWhitelist internal _rewardsWhitelist;

    // oracles
    V2ReservesUniswap internal _v2Res;
    ChainlinkSinglePriceOracle internal _clOracle;
    UniswapV3SinglePriceOracle internal _uniOracle;
    DIAOracleV2SinglePriceOracle internal _diaOracle;
    aspTKNMinimalOracle internal _aspTKNMinOracle1Peas;
    aspTKNMinimalOracle internal _aspTKNMinOracle1Weth;
    aspTKNMinimalOracle internal _aspTKNMinOracle2;
    aspTKNMinimalOracle internal _aspTKNMinOracle4;

    // protocol fees
    ProtocolFees internal _protocolFees;
    ProtocolFeeRouter internal _protocolFeeRouter;

    // pods
    WeightedIndex internal _pod1Peas; // 1 token (Peas)
    WeightedIndex internal _pod1Weth; // 1 token (Weth)
    WeightedIndex internal _pod2; // 2 tokens
    WeightedIndex internal _pod4; // 4 tokens *_*

    WeightedIndex[] internal _pods;

    // index utils
    MockIndexUtils internal _indexUtils;

    // autocompounding
    AutoCompoundingPodLpFactory internal _aspTKNFactory;
    AutoCompoundingPodLp internal _aspTKN1Peas;
    address internal _aspTKN1PeasAddress;
    AutoCompoundingPodLp internal _aspTKN1Weth;
    address internal _aspTKN1WethAddress;
    AutoCompoundingPodLp internal _aspTKN2;
    address internal _aspTKN2Address;
    AutoCompoundingPodLp internal _aspTKN4;
    address internal _aspTKN4Address;

    AutoCompoundingPodLp[] internal _aspTKNs;

    // lvf
    LeverageManager internal _leverageManager;

    // fraxlend
    FraxlendPairDeployer internal _fraxDeployer;
    FraxlendWhitelist internal _fraxWhitelist;
    FraxlendPairRegistry internal _fraxRegistry;
    VariableInterestRate internal _variableInterestRate;

    FraxlendPair internal _fraxLPToken1Peas;
    FraxlendPair internal _fraxLPToken1Weth;
    FraxlendPair internal _fraxLPToken2;
    FraxlendPair internal _fraxLPToken4;

    FraxlendPair[] internal _fraxPairs;

    // flash
    IVault internal _balancerVault;
    BalancerFlashSource internal _balancerFlashSource;
    PodFlashSource internal _podFlashSource;
    UniswapV3FlashSource internal _uniswapV3FlashSourcePeas;
    UniswapV3FlashSource internal _uniswapV3FlashSourceWeth;

    // mocks
    MockUniV3Minter internal _uniV3Minter;
    MockERC20 internal _mockDai;
    WETH9 internal _weth;
    MockERC20 internal _tokenA;
    MockERC20 internal _tokenB;
    MockERC20 internal _tokenC;
    address[] internal tokens = [address(_weth), address(_tokenA), address(_tokenB), address(_tokenC)];

    // mock price feeds
    MockV3Aggregator internal _peasPriceFeed;
    MockV3Aggregator internal _daiPriceFeed;
    MockV3Aggregator internal _wethPriceFeed;
    MockV3Aggregator internal _tokenAPriceFeed;
    MockV3Aggregator internal _tokenBPriceFeed;
    MockV3Aggregator internal _tokenCPriceFeed;

    // uniswap-v2-core
    UniswapV2Factory internal _uniV2Factory;
    UniswapV2Pair internal _uniV2Pool;

    // uniswap-v2-periphery
    UniswapV2Router02 internal _v2SwapRouter;

    // uniswap-v3-core
    UniswapV3Factory internal _uniV3Factory;
    UniswapV3Pool internal _v3peasDaiPool;
    UniswapV3Pool internal _v3peasDaiFlash;
    UniswapV3Pool internal _v3wethDaiFlash;
    UniswapV3Pool internal _v3wethDaiPool;

    // uniswap-v3-periphery
    SwapRouter02 internal _v3SwapRouter;

    // bytecode
    Bytecode internal _bytecode;

    /*///////////////////////////////////////////////////////////////
                            SETUP FUNCTIONS
    ///////////////////////////////////////////////////////////////*/

    function setup() internal {
        _deployUniV3Minter();
        _deployWETH();
        _deployTokens();
        _deployPeas();
        _deployUniV2();
        _deployUniV3();
        _deployProtocolFees();
        _deployRewardsWhitelist();
        _deployTwapUtils();
        _deployDexAdapter();
        _deployIndexUtils();
        _deployPriceFeeds();
        _deployWeightedIndexes();
        _deployAutoCompoundingPodLpFactory();
        _getAutoCompoundingPodLpAddresses();
        _deployAspTKNOracles();
        _deployAspTKNs();
        _deployVariableInterestRate();
        _deployFraxWhitelist();
        _deployFraxPairRegistry();
        _deployFraxPairDeployer();
        _deployFraxPairs();
        _deployLendingAssetVault();
        _deployBalancerVault();
        _deployLeverageManager();
        _deployFlashSources();

        _setupActors();
    }

    function _deployUniV3Minter() internal {
        _uniV3Minter = new MockUniV3Minter();
    }

    function _deployWETH() internal {
        _weth = new WETH9();

        vm.deal(address(this), 1000000 ether);
        _weth.deposit{value: 1000000 ether}();

        vm.deal(address(_uniV3Minter), 2000000 ether);
        vm.prank(address(_uniV3Minter));
        _weth.deposit{value: 2000000 ether}();
    }

    event Message(string a);
    event MessageUint(string a, uint256 b);
    event MessageBool(string a, bool b);
    event MessageAddress(string a, address b);

    function _deployTokens() internal {
        if (address(this) == 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496) {
            _mockDai = new MockERC20();
            _tokenA = new MockERC20();
            _tokenB = new MockERC20();
            _tokenC = new MockERC20();

            _tokenA.initialize("TOKEN A", "TA", 18);
            _tokenB.initialize("TOKEN B", "TB", 6);
            _tokenC.initialize("TOKEN C", "TC", 18);
            bytes memory code = address(_mockDai).code;

            vm.etch(0x6B175474E89094C44Da98b954EedeAC495271d0F, code);

            _mockDai = MockERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
            _mockDai.initialize("MockDAI", "mDAI", 18);

            _mockDai.mint(address(this), 1000000 ether);
            _tokenA.mint(address(this), 1000000 ether);
            _tokenB.mint(address(this), 1000000e6);
            _tokenC.mint(address(this), 1000000 ether);

            _tokenA.mint(address(_uniV3Minter), 1000000 ether);
            _tokenB.mint(address(_uniV3Minter), 100000e6);
            _tokenC.mint(address(_uniV3Minter), 1000000 ether);
            _mockDai.mint(address(_uniV3Minter), 1000000 ether);
        } else {
            _mockDai = MockERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
            _tokenA = new MockERC20();
            _tokenB = new MockERC20();
            _tokenC = new MockERC20();

            _mockDai.initialize("MockDAI", "mDAI", 18);
            _tokenA.initialize("TOKEN A", "TA", 18);
            _tokenB.initialize("TOKEN B", "TB", 6);
            _tokenC.initialize("TOKEN C", "TC", 18);

            _tokenA.mint(address(this), 1000000 ether);
            _tokenB.mint(address(this), 1000000e6);
            _tokenC.mint(address(this), 1000000 ether);
            _mockDai.mint(address(this), 1000000 ether);

            _tokenA.mint(address(_uniV3Minter), 1000000 ether);
            _tokenB.mint(address(_uniV3Minter), 100000e6);
            _tokenC.mint(address(_uniV3Minter), 1000000 ether);
            _mockDai.mint(address(_uniV3Minter), 1000000 ether);
        }
    }

    function _deployPeas() internal {
        _peas = new PEAS("Peapods", "PEAS");

        _peas.transfer(address(_uniV3Minter), 2000000 ether);
    }

    function _deployUniV2() internal {
        _uniV2Factory = new UniswapV2Factory(address(this));
        _v2SwapRouter = new UniswapV2Router02(address(_uniV2Factory), address(_weth));
    }

    function _deployUniV3() internal {
        _uniV3Factory = new UniswapV3Factory();
        _v3peasDaiPool = UniswapV3Pool(_uniV3Factory.createPool(address(_peas), address(_mockDai), 10000));
        _v3peasDaiPool.initialize(1 << 96);
        _v3peasDaiPool.increaseObservationCardinalityNext(600);

        _uniV3Minter.V3addLiquidity(_v3peasDaiPool, 100000e18);
        _v3wethDaiPool = UniswapV3Pool(_uniV3Factory.createPool(address(_weth), address(_mockDai), 10000));
        _v3wethDaiPool.initialize(1 << 96);
        _v3wethDaiPool.increaseObservationCardinalityNext(600);

        _uniV3Minter.V3addLiquidity(_v3wethDaiPool, 100000e18);

        _v3wethDaiFlash = UniswapV3Pool(_uniV3Factory.createPool(address(_weth), address(_mockDai), 500));
        _v3wethDaiFlash.initialize(1 << 96);
        _v3wethDaiFlash.increaseObservationCardinalityNext(600);

        _uniV3Minter.V3addLiquidity(_v3wethDaiFlash, 100000e18);

        _v3peasDaiFlash = UniswapV3Pool(_uniV3Factory.createPool(address(_peas), address(_mockDai), 500));
        _v3peasDaiFlash.initialize(1 << 96);
        _v3peasDaiFlash.increaseObservationCardinalityNext(600);

        _uniV3Minter.V3addLiquidity(_v3peasDaiFlash, 100000e18);

        _v3SwapRouter = new SwapRouter02(address(_uniV2Factory), address(_uniV3Factory), address(0), address(_weth));
    }

    function _deployProtocolFees() internal {
        _protocolFees = new ProtocolFees();
        _protocolFees.setYieldAdmin(500);
        _protocolFees.setYieldBurn(500);

        if (address(this) == 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496) {
            _protocolFeeRouter = new ProtocolFeeRouter(_protocolFees);

            bytes memory code = address(_protocolFeeRouter).code;
            vm.etch(0x7d544DD34ABbE24C8832db27820Ff53C151e949b, code);

            _protocolFeeRouter = ProtocolFeeRouter(0x7d544DD34ABbE24C8832db27820Ff53C151e949b);

            vm.prank(_protocolFeeRouter.owner());
            _protocolFeeRouter.transferOwnership(address(this));

            _protocolFeeRouter.setProtocolFees(_protocolFees);
        } else {
            _protocolFeeRouter = ProtocolFeeRouter(0x7d544DD34ABbE24C8832db27820Ff53C151e949b);

            vm.prank(_protocolFeeRouter.owner());
            _protocolFeeRouter.transferOwnership(address(this));

            _protocolFeeRouter.setProtocolFees(_protocolFees);
        }
    }

    function _deployRewardsWhitelist() internal {
        if (address(this) == 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496) {
            _rewardsWhitelist = new RewardsWhitelist();

            bytes memory code = address(_rewardsWhitelist).code;
            vm.etch(0xEc0Eb48d2D638f241c1a7F109e38ef2901E9450F, code);

            _rewardsWhitelist = RewardsWhitelist(0xEc0Eb48d2D638f241c1a7F109e38ef2901E9450F);

            vm.prank(_rewardsWhitelist.owner());
            _rewardsWhitelist.transferOwnership(address(this));

            _rewardsWhitelist.toggleRewardsToken(address(_peas), true);
        } else {
            _rewardsWhitelist = RewardsWhitelist(0xEc0Eb48d2D638f241c1a7F109e38ef2901E9450F);

            vm.prank(_rewardsWhitelist.owner());
            _rewardsWhitelist.transferOwnership(address(this));

            _rewardsWhitelist.toggleRewardsToken(address(_peas), true);
        }
    }

    function _deployTwapUtils() internal {
        if (address(this) == 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496) {
            _twapUtils = new MockV3TwapUtilities();

            bytes memory code = address(_twapUtils).code;
            vm.etch(0x024ff47D552cB222b265D68C7aeB26E586D5229D, code);

            // fl.log("TWAP UTILS CODE", code);
            // fl.log("TWAP UTILS CREATION CODE", type(MockV3TwapUtilities).creationCode);
            // // abi.encodePacked(bytecode, abi.encode(arg1, arg2)) // @audit this was for reference. None of these contracts have constructor args
            // @audit this is how I've been getting creationCode!!!

            _twapUtils = MockV3TwapUtilities(0x024ff47D552cB222b265D68C7aeB26E586D5229D);
        } else {
            _twapUtils = MockV3TwapUtilities(0x024ff47D552cB222b265D68C7aeB26E586D5229D);
        }
    }

    function _deployDexAdapter() internal {
        _dexAdapter = new UniswapDexAdapter(_twapUtils, address(_v2SwapRouter), address(_v3SwapRouter), false);
    }

    function _deployIndexUtils() internal {
        _indexUtils = new MockIndexUtils(_twapUtils, _dexAdapter, address(_v3SwapRouter));
    }

    function _deployPriceFeeds() internal {
        _peasPriceFeed = new MockV3Aggregator(_peas.decimals(), 3e18);
        _peasPrice = 3e18;
        _daiPriceFeed = new MockV3Aggregator(_mockDai.decimals(), 1e18);
        _daiPrice = 1e18;
        _wethPriceFeed = new MockV3Aggregator(_weth.decimals(), 3000e18);
        _wethPrice = 3000e18;
        _tokenAPriceFeed = new MockV3Aggregator(_tokenA.decimals(), 1e18);
        _tokenAPrice = 1e18;
        _tokenBPriceFeed = new MockV3Aggregator(_tokenB.decimals(), 100e6);
        _tokenBPrice = 100e6;
        _tokenCPriceFeed = new MockV3Aggregator(_tokenC.decimals(), 50e18);
        _tokenCPrice = 50e18;
    }

    function _deployWeightedIndexes() internal {
        IDecentralizedIndex.Config memory _c;
        IDecentralizedIndex.Fees memory _f;
        _f.bond = fee;
        _f.debond = fee;

        // POD1 (Peas)
        address[] memory _t1 = new address[](1);
        _t1[0] = address(_peas);
        uint256[] memory _w1 = new uint256[](1);
        _w1[0] = 100;
        address __pod1Peas = _createPod(
            "Weth Pod",
            "pPeas",
            _c,
            _f,
            _t1,
            _w1,
            address(0),
            false,
            abi.encode(
                address(_mockDai),
                address(_peas),
                address(_mockDai),
                address(_protocolFeeRouter),
                address(_rewardsWhitelist),
                address(_twapUtils),
                address(_dexAdapter)
            )
        );
        _pod1Peas = WeightedIndex(payable(__pod1Peas));

        // approve pod asset & pair asset
        _peas.approve(address(_pod1Peas), type(uint256).max);
        _mockDai.approve(address(_pod1Peas), type(uint256).max);
        // mint some pTKNs
        _pod1Peas.bond(address(_peas), 1 ether, 1 ether);
        // add Liquidity
        _pod1Peas.addLiquidityV2(1 ether, 1 ether, 100, block.timestamp);

        // add to array for fuzzing
        _pods.push(_pod1Peas);

        // POD1 (Weth)
        address[] memory _t1W = new address[](1);
        _t1W[0] = address(_weth);
        uint256[] memory _w1W = new uint256[](1);
        _w1W[0] = 100;
        address __pod1Weth = _createPod(
            "Weth Pod",
            "pWeth",
            _c,
            _f,
            _t1W,
            _w1W,
            address(0),
            false,
            abi.encode(
                address(_mockDai),
                address(_peas),
                address(_mockDai),
                address(_protocolFeeRouter),
                address(_rewardsWhitelist),
                address(_twapUtils),
                address(_dexAdapter)
            )
        );
        _pod1Weth = WeightedIndex(payable(__pod1Weth));

        // approve pod asset & pair asset
        _weth.approve(address(_pod1Weth), type(uint256).max);
        _mockDai.approve(address(_pod1Weth), type(uint256).max);
        // mint some pTKNs
        _pod1Weth.bond(address(_weth), 1 ether, 1 ether);
        // add Liquidity
        _pod1Weth.addLiquidityV2(1 ether, 1 ether, 100, block.timestamp);

        // add to array for fuzzing
        _pods.push(_pod1Weth);

        // POD2
        address[] memory _t2 = new address[](2);
        _t2[0] = address(_peas);
        _t2[1] = address(_weth);
        uint256[] memory _w2 = new uint256[](2);
        _w2[0] = 50;
        _w2[1] = 50;
        address __pod2 = _createPod(
            "Test2",
            "pTEST2",
            _c,
            _f,
            _t2,
            _w2,
            address(0),
            false,
            abi.encode(
                address(_mockDai),
                address(_peas),
                address(_mockDai),
                address(_protocolFeeRouter),
                address(_rewardsWhitelist),
                address(_twapUtils),
                address(_dexAdapter)
            )
        );
        _pod2 = WeightedIndex(payable(__pod2));

        // approve pod asset & pair asset
        _peas.approve(address(_pod2), type(uint256).max);
        _weth.approve(address(_pod2), type(uint256).max);
        _mockDai.approve(address(_pod2), type(uint256).max);
        // mint some pTKNs
        _pod2.bond(address(_peas), 100 ether, 100 ether);
        // add Liquidity
        _pod2.addLiquidityV2(100 ether, 100 ether, 100, block.timestamp);

        // add to array for fuzzing
        _pods.push(_pod2);

        // POD4
        address __pod4 = _deployPod4(_c, _f);
        _pod4 = WeightedIndex(payable(__pod4));

        // approve pod asset & pair asset
        _weth.approve(address(_pod4), type(uint256).max);
        _tokenA.approve(address(_pod4), type(uint256).max);
        _tokenB.approve(address(_pod4), type(uint256).max);
        _tokenC.approve(address(_pod4), type(uint256).max);
        _mockDai.approve(address(_pod4), type(uint256).max);
        // mint some pTKNs
        _pod4.bond(address(_weth), 1 ether, 1 ether);
        // add Liquidity
        _pod4.addLiquidityV2(1 ether, 1 ether, 100, block.timestamp);

        // add to array for fuzzing
        _pods.push(_pod4);
    }

    function _deployPod4(IDecentralizedIndex.Config memory _c, IDecentralizedIndex.Fees memory _f)
        internal
        returns (address __pod4)
    {
        address[] memory _t4 = new address[](4);
        _t4[0] = address(_weth);
        _t4[1] = address(_tokenA);
        _t4[2] = address(_tokenB);
        _t4[3] = address(_tokenC);
        uint256[] memory _w4 = new uint256[](4);
        _w4[0] = 25;
        _w4[1] = 25;
        _w4[2] = 25;
        _w4[3] = 25;
        __pod4 = _createPod(
            "Test4",
            "pTEST4",
            _c,
            _f,
            _t4,
            _w4,
            address(0),
            false,
            abi.encode(
                address(_mockDai),
                address(_peas),
                address(_mockDai),
                address(_protocolFeeRouter),
                address(_rewardsWhitelist),
                address(_twapUtils),
                address(_dexAdapter)
            )
        );
    }

    function _deployAutoCompoundingPodLpFactory() internal {
        _aspTKNFactory = new AutoCompoundingPodLpFactory();
    }

    function _getAutoCompoundingPodLpAddresses() internal {
        _aspTKN1PeasAddress = _aspTKNFactory.getNewCaFromParams(
            "Test aspTKN1Peas", "aspTKN1Peas", false, _pod1Peas, _dexAdapter, _indexUtils, 0
        );

        _aspTKN1WethAddress = _aspTKNFactory.getNewCaFromParams(
            "Test aspTKN1Weth", "aspTKN1Weth", false, _pod1Weth, _dexAdapter, _indexUtils, 0
        );

        _aspTKN2Address =
            _aspTKNFactory.getNewCaFromParams("Test aspTKN2", "aspTKN2", false, _pod2, _dexAdapter, _indexUtils, 0);

        _aspTKN4Address =
            _aspTKNFactory.getNewCaFromParams("Test aspTKN4", "aspTKN4", false, _pod4, _dexAdapter, _indexUtils, 0);
    }

    function _deployAspTKNOracles() internal {
        _v2Res = new V2ReservesUniswap();
        _clOracle = new ChainlinkSinglePriceOracle(address(0));
        _uniOracle = new UniswapV3SinglePriceOracle(address(0));
        _diaOracle = new DIAOracleV2SinglePriceOracle(address(0));

        _aspTKNMinOracle1Peas = new aspTKNMinimalOracle(
            _aspTKN1PeasAddress,
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                address(_mockDai), // DAI
                false,
                _pod1Peas.lpStakingPool(),
                address(_v3peasDaiPool), // UniV3: PEAS / DAI
                address(_daiPriceFeed) // CL: DAI / USD
            ),
            abi.encode(address(0), address(0), address(0), address(0), address(_v2Res))
        );

        emit MessageAddress("aspTkn1", address(_aspTKNMinOracle1Peas));

        _aspTKNMinOracle1Weth = new aspTKNMinimalOracle(
            _aspTKN1WethAddress,
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                address(_mockDai), // DAI
                false,
                _pod1Weth.lpStakingPool(),
                address(_v3wethDaiPool), // UniV3: WETH / DAI
                address(_daiPriceFeed) // CL: DAI / USD
            ),
            abi.encode(address(0), address(0), address(0), address(0), address(_v2Res))
        );

        _aspTKNMinOracle2 = new aspTKNMinimalOracle(
            _aspTKN2Address,
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                address(_mockDai), // DAI
                false,
                _pod2.lpStakingPool(),
                address(_v3peasDaiPool), // UniV3: PEAS / DAI
                address(_daiPriceFeed) // CL: DAI / USD
            ),
            abi.encode(address(0), address(0), address(0), address(0), address(_v2Res))
        );

        _aspTKNMinOracle4 = new aspTKNMinimalOracle(
            _aspTKN4Address,
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                address(_mockDai), // DAI
                false,
                _pod4.lpStakingPool(),
                address(_v3wethDaiPool), // UniV3: WETH / DAI
                address(_daiPriceFeed) // CL: DAI / USD
            ),
            abi.encode(address(0), address(0), address(0), address(0), address(_v2Res))
        );
    }

    function _deployAspTKNs() internal {
        address _lpPeas = _pod1Peas.lpStakingPool();
        address _stakingPeas = StakingPoolToken(_lpPeas).stakingToken();
        // Approve pod LP token
        IERC20(_stakingPeas).approve(_lpPeas, 1000);
        // Stake liquidity tokens for initial aspTKN deposit
        StakingPoolToken(_lpPeas).stake(address(this), 1000);
        // Approve staking token for min deposit
        IERC20(_lpPeas).approve(address(_aspTKNFactory), 1000);

        _aspTKNFactory.create("Test aspTKN1Peas", "aspTKN1Peas", false, _pod1Peas, _dexAdapter, _indexUtils, 0);
        _aspTKN1Peas = AutoCompoundingPodLp(_aspTKN1PeasAddress);

        // add to array for fuzzing
        _aspTKNs.push(_aspTKN1Peas);

        address _lpWeth = _pod1Weth.lpStakingPool();
        address _stakingWeth = StakingPoolToken(_lpWeth).stakingToken();
        // Approve pod LP token
        IERC20(_stakingWeth).approve(_lpWeth, 1000);
        // Stake liquidity tokens for initial aspTKN deposit
        StakingPoolToken(_lpWeth).stake(address(this), 1000);
        // Approve staking token for min deposit
        IERC20(_lpWeth).approve(address(_aspTKNFactory), 1000);

        _aspTKNFactory.create("Test aspTKN1Weth", "aspTKN1Weth", false, _pod1Weth, _dexAdapter, _indexUtils, 0);
        _aspTKN1Weth = AutoCompoundingPodLp(_aspTKN1WethAddress);

        // add to array for fuzzing
        _aspTKNs.push(_aspTKN1Weth);

        address _lpToken2 = _pod2.lpStakingPool();
        address _stakingToken2 = StakingPoolToken(_lpToken2).stakingToken();
        // Approve pod LP token
        IERC20(_stakingToken2).approve(_lpToken2, 1000);
        // Stake liquidity tokens for initial aspTKN deposit
        StakingPoolToken(_lpToken2).stake(address(this), 1000);
        // Approve staking token for min deposit
        IERC20(_lpToken2).approve(address(_aspTKNFactory), 1000);

        _aspTKNFactory.create("Test aspTKN2", "aspTKN2", false, _pod2, _dexAdapter, _indexUtils, 0);
        _aspTKN2 = AutoCompoundingPodLp(_aspTKN2Address);

        // add to array for fuzzing
        _aspTKNs.push(_aspTKN2);

        address _lpToken4 = _pod4.lpStakingPool();
        address _stakingToken4 = StakingPoolToken(_lpToken4).stakingToken();
        // Approve pod LP token
        IERC20(_stakingToken4).approve(_lpToken4, 1000);
        // Stake liquidity tokens for initial aspTKN deposit
        StakingPoolToken(_lpToken4).stake(address(this), 1000);
        // Approve staking token for min deposit
        IERC20(_lpToken4).approve(address(_aspTKNFactory), 1000);

        _aspTKNFactory.create("Test aspTKN4", "aspTKN4", false, _pod4, _dexAdapter, _indexUtils, 0);
        _aspTKN4 = AutoCompoundingPodLp(_aspTKN4Address);

        // add to array for fuzzing
        _aspTKNs.push(_aspTKN4);
    }

    function _deployVariableInterestRate() internal {
        // These values taken from existing Fraxlend Variable Rate Contract
        _variableInterestRate = new VariableInterestRate(
            "[0.5 0.2@.875 5-10k] 2 days (.75-.85)",
            87500,
            200000000000000000,
            75000,
            85000,
            158247046,
            1582470460,
            3164940920000,
            172800
        );
    }

    function _deployFraxWhitelist() internal {
        _fraxWhitelist = new FraxlendWhitelist();
    }

    function _deployFraxPairRegistry() internal {
        address[] memory _initialDeployers = new address[](0);
        _fraxRegistry = new FraxlendPairRegistry(address(this), _initialDeployers);
    }

    function _deployFraxPairDeployer() internal {
        ConstructorParams memory _params =
            ConstructorParams(circuitBreaker, comptroller, timelock, address(_fraxWhitelist), address(_fraxRegistry));
        _fraxDeployer = new FraxlendPairDeployer(_params);

        _fraxDeployer.setCreationCode(type(FraxlendPair).creationCode);

        address[] memory _whitelistDeployer = new address[](1);
        _whitelistDeployer[0] = address(this);

        _fraxWhitelist.setFraxlendDeployerWhitelist(_whitelistDeployer, true);

        address[] memory _registryDeployer = new address[](1);
        _registryDeployer[0] = address(_fraxDeployer);

        _fraxRegistry.setDeployers(_registryDeployer, true);
        emit Message("1");
    }

    function _deployFraxPairs() internal {
        // moving time to help out the twap
        vm.warp(block.timestamp + 1 days);

        _updatePrices(block.timestamp);

        emit Message("1aa");

        _fraxLPToken1Peas = FraxlendPair(
            _fraxDeployer.deploy(
                abi.encode(
                    _pod1Peas.PAIRED_LP_TOKEN(), // asset
                    _aspTKN1PeasAddress, // collateral
                    address(_aspTKNMinOracle1Peas), //oracle
                    5000, // maxOracleDeviation
                    address(_variableInterestRate), //rateContract
                    1000, //fullUtilizationRate
                    75000, // maxLtv
                    10000, // uint256 _cleanLiquidationFee
                    9000, // uint256 _dirtyLiquidationFee
                    2000 //uint256 _protocolLiquidationFee
                )
            )
        );

        emit Message("1b");

        // deposit some asset
        IERC20(_pod1Peas.PAIRED_LP_TOKEN()).approve(address(_fraxLPToken1Peas), type(uint256).max);
        _fraxLPToken1Peas.deposit(100000 ether, address(this));

        emit Message("2");

        // add to array for fuzzing
        _fraxPairs.push(_fraxLPToken1Peas);

        _fraxLPToken1Weth = FraxlendPair(
            _fraxDeployer.deploy(
                abi.encode(
                    _pod1Weth.PAIRED_LP_TOKEN(),
                    _aspTKN1WethAddress,
                    address(_aspTKNMinOracle1Weth),
                    5000,
                    address(_variableInterestRate),
                    1000,
                    75000,
                    10000,
                    9000,
                    2000
                )
            )
        );

        // deposit some asset
        IERC20(_pod1Weth.PAIRED_LP_TOKEN()).approve(address(_fraxLPToken1Weth), type(uint256).max);
        _fraxLPToken1Weth.deposit(100000 ether, address(this));

        // add to array for fuzzing
        _fraxPairs.push(_fraxLPToken1Weth);

        _fraxLPToken2 = FraxlendPair(
            _fraxDeployer.deploy(
                abi.encode(
                    _pod2.PAIRED_LP_TOKEN(),
                    _aspTKN2Address,
                    address(_aspTKNMinOracle2),
                    5000,
                    address(_variableInterestRate),
                    1000,
                    75000,
                    10000,
                    9000,
                    2000
                )
            )
        );

        // deposit some asset
        IERC20(_pod2.PAIRED_LP_TOKEN()).approve(address(_fraxLPToken2), type(uint256).max);
        _fraxLPToken2.deposit(100000 ether, address(this));

        // add to array for fuzzing
        _fraxPairs.push(_fraxLPToken2);

        _fraxLPToken4 = FraxlendPair(
            _fraxDeployer.deploy(
                abi.encode(
                    _pod4.PAIRED_LP_TOKEN(),
                    _aspTKN4Address,
                    address(_aspTKNMinOracle4),
                    5000,
                    address(_variableInterestRate),
                    1000,
                    75000,
                    10000,
                    9000,
                    2000
                )
            )
        );

        // deposit some asset
        IERC20(_pod4.PAIRED_LP_TOKEN()).approve(address(_fraxLPToken4), type(uint256).max);
        _fraxLPToken4.deposit(100000 ether, address(this));

        // add to array for fuzzing
        _fraxPairs.push(_fraxLPToken4);
    }

    function _deployLendingAssetVault() internal {
        _lendingAssetVault = new LendingAssetVault("Test LAV", "tLAV", address(_mockDai));

        IERC20 vaultAsset1Peas = IERC20(_fraxLPToken1Peas.asset());
        vaultAsset1Peas.approve(address(_fraxLPToken1Peas), vaultAsset1Peas.totalSupply());
        vaultAsset1Peas.approve(address(_lendingAssetVault), vaultAsset1Peas.totalSupply());
        _lendingAssetVault.setVaultWhitelist(address(_fraxLPToken1Peas), true);

        // set external access vault for fraxLendingPair
        vm.prank(timelock);
        _fraxLPToken1Peas.setExternalAssetVault(IERC4626Extended(address(_lendingAssetVault)));

        IERC20 vaultAsset1Weth = IERC20(_fraxLPToken1Weth.asset());
        vaultAsset1Weth.approve(address(_fraxLPToken1Weth), vaultAsset1Weth.totalSupply());
        vaultAsset1Weth.approve(address(_lendingAssetVault), vaultAsset1Weth.totalSupply());
        _lendingAssetVault.setVaultWhitelist(address(_fraxLPToken1Weth), true);

        // set external access vault
        vm.prank(timelock);
        _fraxLPToken1Weth.setExternalAssetVault(IERC4626Extended(address(_lendingAssetVault)));

        IERC20 vaultAsset2 = IERC20(_fraxLPToken2.asset());
        vaultAsset2.approve(address(_fraxLPToken2), vaultAsset2.totalSupply());
        vaultAsset2.approve(address(_lendingAssetVault), vaultAsset2.totalSupply());
        _lendingAssetVault.setVaultWhitelist(address(_fraxLPToken2), true);

        // set external access vault
        vm.prank(timelock);
        _fraxLPToken2.setExternalAssetVault(IERC4626Extended(address(_lendingAssetVault)));

        IERC20 vaultAsset4 = IERC20(_fraxLPToken4.asset());
        vaultAsset4.approve(address(_fraxLPToken4), vaultAsset4.totalSupply());
        vaultAsset4.approve(address(_lendingAssetVault), vaultAsset4.totalSupply());
        _lendingAssetVault.setVaultWhitelist(address(_fraxLPToken4), true);

        // set external access vault
        vm.prank(timelock);
        _fraxLPToken4.setExternalAssetVault(IERC4626Extended(address(_lendingAssetVault)));

        address[] memory vaultAddresses = new address[](4);
        vaultAddresses[0] = address(_fraxLPToken1Peas);
        vaultAddresses[1] = address(_fraxLPToken1Weth);
        vaultAddresses[2] = address(_fraxLPToken2);
        vaultAddresses[3] = address(_fraxLPToken4);

        _lendingAssetVault.setVaultMaxAllocation(vaultAddresses, _fraxPercentages);
    }

    function _deployBalancerVault() internal {
        _bytecode = new Bytecode();
        if (address(this) == 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496) {
            vm.etch(0xBA12222222228d8Ba445958a75a0704d566BF2C8, _bytecode.BALANCER_VAULT_BYTECODE());

            _balancerVault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
        } else {
            _balancerVault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
        }
    }

    function _deployLeverageManager() internal {
        _leverageManager = new LeverageManager("Test LM", "tLM", IIndexUtils(address(_indexUtils)));

        _leverageManager.setLendingPair(address(_pod1Peas), address(_fraxLPToken1Peas));
        _leverageManager.setLendingPair(address(_pod1Weth), address(_fraxLPToken1Weth));
        _leverageManager.setLendingPair(address(_pod2), address(_fraxLPToken2));
        _leverageManager.setLendingPair(address(_pod4), address(_fraxLPToken4));
    }

    function _deployFlashSources() internal {
        // _balancerFlashSource = new BalancerFlashSource(address(_leverageManager));
        // _podFlashSource = new PodFlashSource(
        //     address(_pod1Peas),
        //     address(_mockDai),
        //     address(_leverageManager)
        //     );
        _uniswapV3FlashSourcePeas = new UniswapV3FlashSource(address(_v3peasDaiFlash), address(_leverageManager));
        _uniswapV3FlashSourceWeth = new UniswapV3FlashSource(address(_v3wethDaiFlash), address(_leverageManager));

        _leverageManager.setFlashSource(address(_pod1Peas.PAIRED_LP_TOKEN()), address(_uniswapV3FlashSourcePeas));
        _leverageManager.setFlashSource(address(_pod1Weth.PAIRED_LP_TOKEN()), address(_uniswapV3FlashSourceWeth));
        _leverageManager.setFlashSource(address(_pod2.PAIRED_LP_TOKEN()), address(_uniswapV3FlashSourcePeas));
        _leverageManager.setFlashSource(address(_pod4.PAIRED_LP_TOKEN()), address(_uniswapV3FlashSourceWeth));
    }

    /*////////////////////////////////////////////////////////////////
                                    HELPERS
    ////////////////////////////////////////////////////////////////*/

    function _setupActors() internal {
        for (uint256 i; i < users.length; i++) {
            vm.deal(users[i], 1000000 ether);
            vm.prank(users[i]);
            _weth.deposit{value: 1000000 ether}();

            _tokenA.mint(users[i], 1000000 ether);
            _tokenB.mint(users[i], 1000000e6);
            _tokenC.mint(users[i], 1000000 ether);
            _mockDai.mint(users[i], 1000000 ether);

            _peas.transfer(users[i], 1000000 ether);
        }
    }

    function randomAddress(uint256 seed) internal view returns (address) {
        return users[bound(seed, 0, users.length - 1)];
    }

    function randomPod(uint256 seed) internal view returns (WeightedIndex) {
        return _pods[bound(seed, 0, _pods.length - 1)];
    }

    function randomIndexToken(WeightedIndex pod, uint256 seed) internal view returns (address) {
        IDecentralizedIndex.IndexAssetInfo[] memory indexTokens = pod.getAllAssets();
        return indexTokens[bound(seed, 0, indexTokens.length - 1)].token;
    }

    function randomAspTKN(uint256 seed) internal view returns (AutoCompoundingPodLp) {
        return _aspTKNs[bound(seed, 0, _aspTKNs.length - 1)];
    }

    function randomFraxPair(uint256 seed) internal view returns (FraxlendPair) {
        return _fraxPairs[bound(seed, 0, _fraxPairs.length - 1)];
    }

    function _approveIndexTokens(WeightedIndex pod, address user, uint256) internal {
        IDecentralizedIndex.IndexAssetInfo[] memory indexTokens = pod.getAllAssets();

        for (uint256 i; i < indexTokens.length; i++) {
            vm.prank(user);
            MockERC20(indexTokens[i].token).approve(address(pod), type(uint256).max);
        }
    }

    function _checkTokenBalances(WeightedIndex pod, address token, address user, uint256 amount)
        internal
        view
        returns (bool hasEnough)
    {
        IDecentralizedIndex.IndexAssetInfo[] memory indexTokens = pod.getAllAssets();

        hasEnough = true;
        for (uint256 i; i < indexTokens.length; i++) {
            uint256 amountNeeded = pod.getInitialAmount(token, amount, indexTokens[i].token);

            if (amountNeeded > IERC20(indexTokens[i].token).balanceOf(user)) {
                hasEnough = false;
                break;
            }
        }
    }

    function _updatePrices(uint256 seed) internal {
        _peasPrice = randomPrice(seed, _peasPrice);
        _peasPriceFeed.updateAnswer(int256(_peasPrice));

        _daiPrice = randomPrice(seed, _daiPrice);
        _daiPriceFeed.updateAnswer(int256(_daiPrice));

        _wethPrice = randomPrice(seed, _wethPrice);
        _wethPriceFeed.updateAnswer(int256(_wethPrice));

        _tokenAPrice = randomPrice(seed, _tokenAPrice);
        _tokenAPriceFeed.updateAnswer(int256(_tokenAPrice));

        _tokenBPrice = randomPrice(seed, _tokenBPrice);
        _tokenBPriceFeed.updateAnswer(int256(_tokenBPrice));

        _tokenCPrice = randomPrice(seed, _tokenCPrice);
        _tokenCPriceFeed.updateAnswer(int256(_tokenCPrice));
    }

    function randomPrice(uint256 seed, uint256 price) internal pure returns (uint256) {
        uint256 newPrice;
        newPrice = bound(seed, (price * 9e18) / 10e18, (price * 11e18) / 10e18);
        return newPrice;
    }

    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function assertApproxEq(uint256 a, uint256 b, uint256 maxDelta, string memory reason) internal {
        if (!(a == b)) {
            uint256 dt = b > a ? b - a : a - b;
            if (dt > maxDelta) {
                emit log("Error: a =~ b not satisfied [uint]");
                emit log_named_uint("   Value a", a);
                emit log_named_uint("   Value b", b);
                emit log_named_uint(" Max Delta", maxDelta);
                emit log_named_uint("     Delta", dt);
                fl.t(false, reason);
            }
        } else {
            fl.t(true, "a == b");
        }
    }

    function assertApproxLte(uint256 a, uint256 b, uint256 maxDelta, string memory reason) internal {
        if (!(a <= b)) {
            uint256 dt = b > a ? b - a : a - b;
            if (dt > maxDelta) {
                emit log("Error: a =~ b not satisfied [uint]");
                emit log_named_uint("   Value a", a);
                emit log_named_uint("   Value b", b);
                emit log_named_uint(" Max Delta", maxDelta);
                emit log_named_uint("     Delta", dt);
                fl.t(false, reason);
            }
        } else {
            fl.t(true, "a == b");
        }
    }

    function getPanicCode(bytes memory revertData) internal returns (uint256) {
        fl.log("REVERT DATA LENGTH", revertData.length);
        if (revertData.length < 36) return 0;

        uint256 panicCode;
        assembly {
            panicCode := mload(add(revertData, 36))
        }
        return panicCode;
    }
}

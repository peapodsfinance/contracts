// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IDecentralizedIndex} from "../../contracts/interfaces/IDecentralizedIndex.sol";
import {IIndexUtils} from "../../contracts/interfaces/IIndexUtils.sol";
import {ITokenRewards} from "../../contracts/interfaces/ITokenRewards.sol";
import {IStakingPoolToken} from "../../contracts/interfaces/IStakingPoolToken.sol";

import {IndexUtils} from "../../contracts/IndexUtils.sol";

import {AutoCompoundingPodLp} from "../../contracts/AutoCompoundingPodLp.sol";
import {RewardsWhitelist} from "../../contracts/RewardsWhitelist.sol";
import {WeightedIndex} from "../../contracts/WeightedIndex.sol";
import {PEAS} from "../../contracts/PEAS.sol";
import {V3TwapUtilities} from "../../contracts/twaputils/V3TwapUtilities.sol";
import {UniswapDexAdapter} from "../../contracts/dex/UniswapDexAdapter.sol";
import {BalancerFlashSource} from "../../contracts/flash/BalancerFlashSource.sol";
import {LeverageManager} from "../../contracts/lvf/LeverageManager.sol";

import {FraxlendPairDeployer, ConstructorParams} from "@fraxlend/FraxlendPairDeployer.sol";
import {FraxlendWhitelist} from "@fraxlend/FraxlendWhitelist.sol";
import {FraxlendPairRegistry} from "@fraxlend/FraxlendPairRegistry.sol";
import {FraxlendPair} from "@fraxlend/FraxlendPair.sol";
import {VariableInterestRate} from "@fraxlend/VariableInterestRate.sol";
import {IERC4626Extended} from "@fraxlend/interfaces/IERC4626Extended.sol";

import {LendingAssetVault} from "contracts/LendingAssetVault.sol";
import {MockDualOracle} from "../mocks/MockDualOracle.sol";

import "../../contracts/interfaces/IDexAdapter.sol";
import "../../contracts/interfaces/ISwapRouter02.sol";
import "../../contracts/interfaces/IUniswapV2Factory.sol";
import "../../contracts/interfaces/IUniswapV2Pair.sol";
import "../../contracts/interfaces/IUniswapV2Router02.sol";
import "../../contracts/interfaces/IV3TwapUtilities.sol";

import {PodHelperTest} from "./PodHelper.t.sol";

import {console} from "forge-std/console.sol";

contract LivePOC is PodHelperTest {
    FraxlendPairDeployer deployer;
    FraxlendPair pair;
    ERC20 DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    VariableInterestRate _variableInterestRate;
    MockDualOracle oracle;
    FraxlendWhitelist _fraxWhitelist;
    FraxlendPairRegistry _fraxRegistry;
    uint256[] internal _fraxPercentages = [10000e18];
    LendingAssetVault _lendingAssetVault;

    // New stuff
    LeverageManager public leverageManager;
    IndexUtils public idxUtils;
    RewardsWhitelist public whitelister;
    V3TwapUtilities public twapUtils;
    UniswapDexAdapter public dexAdapter;
    WeightedIndex public pod;
    WeightedIndex public selfLendingPod;

    BalancerFlashSource public flashSource;

    address public spTkn;
    address public selfLending_spTkn;

    AutoCompoundingPodLp public aspTkn;
    AutoCompoundingPodLp public selfLending_aspTkn;

    address public constant ALICE = address(0x1);
    address public constant BOB = address(0x2);
    uint256 public constant INITIAL_BALANCE = 1000000 * 1e18;

    address public weth;
    PEAS peas;

    // fraxlend protocol actors
    address internal comptroller = vm.addr(uint256(keccak256("comptroller")));
    address internal circuitBreaker = vm.addr(uint256(keccak256("circuitBreaker")));
    address internal timelock = vm.addr(uint256(keccak256("comptroller")));

    address public attacker = makeAddr("attacker");
    address public user;

    function setUp() public override {
        // vm.createSelectFork(vm.envString("RPC"));
        super.setUp();

        peas = PEAS(0x02f92800F57BCD74066F5709F1Daa1A4302Df875);
        weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        user = makeAddr("user");
        deal(address(DAI), user, 10_000e18);
        deal(address(weth), user, 10_000e18);
        deal(address(peas), user, 10_000e18);

        // PART 1
        uint16 fee = 100;

        whitelister = new RewardsWhitelist();
        twapUtils = new V3TwapUtilities();
        dexAdapter = new UniswapDexAdapter(
            twapUtils,
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, // Uniswap V2 Router
            0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45, // Uniswap SwapRouter02
            false
        );
        vm.label(address(dexAdapter), "UniswapDexAdapter");
        idxUtils = new IndexUtils(twapUtils, dexAdapter);

        IDecentralizedIndex.Config memory _c;
        IDecentralizedIndex.Fees memory _f;
        _f.bond = fee;
        _f.debond = fee;
        address[] memory _t = new address[](1);
        _t[0] = address(DAI);
        uint256[] memory _w = new uint256[](1);
        _w[0] = 100;
        vm.label(address(idxUtils), "IndexUtils");
        address _pod = _createPod(
            "Test",
            "pTEST",
            _c,
            _f,
            _t,
            _w,
            address(0),
            false,
            abi.encode(
                address(DAI), // _pairedLpToken
                address(peas), // _lpRewardsToken
                0x6B175474E89094C44Da98b954EedeAC495271d0F, // _dai
                0x7d544DD34ABbE24C8832db27820Ff53C151e949b, // _feeRouter
                whitelister, // _rewardsWhitelister
                0x024ff47D552cB222b265D68C7aeB26E586D5229D, // _v3TwapUtils
                dexAdapter // _dexAdapter
            )
        );
        pod = WeightedIndex(payable(_pod));
        vm.label(address(pod), "Pod");

        // mocking some liquidity in the pool
        address uni_pair =
            IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f).getPair(address(DAI), address(pod));
        // IUniswapV2Router02 router = IUniswapV2Router02(
        //     0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        // );

        //@e SEEDING INITIAL LIQ
        deal(address(DAI), address(this), 100000e18);
        IERC20(address(DAI)).approve(address(pod), type(uint256).max);
        pod.bond(address(DAI), 50_000e18, 0);
        pod.addLiquidityV2(40_000e18, 40_000e18, 1000, block.timestamp + 50);

        spTkn = pod.lpStakingPool();
        aspTkn = new AutoCompoundingPodLp("aspTkn", "aspTkn", false, pod, dexAdapter, idxUtils);

        leverageManager = new LeverageManager("Leverage Position", "LP", idxUtils);
        flashSource = new BalancerFlashSource(address(leverageManager));

        // PART 2
        oracle = new MockDualOracle(); //@audit NOTE that we CANT test liquidations in this fork test. Mainly for other stuff.

        _deployVariableInterestRate();
        _deployFraxWhitelist();
        _deployFraxPairRegistry();
        _deployFraxPairDeployer();
        _deployFraxPairs();
        _deployLendingAssetVault();

        // Setup LeverageManager
        leverageManager.setLendingPair(address(pod), address(pair));
        leverageManager.setFlashSource(address(DAI), address(flashSource));

        deal(address(DAI), address(this), 100_000 * 1e18);
        IERC20(address(DAI)).approve(address(pair), 10_000 * 1e18);
        IERC20(address(DAI)).approve(address(_lendingAssetVault), 10_000 * 1e18);
        _lendingAssetVault.deposit(1000e18, address(this));
        pair.deposit(10_000 * 1e18, address(this));

        // ALSO: setup a self lending pod
        _deploySelfLendingPod();

        //@e MY SETUP
        whitelister.toggleRewardsToken(weth, true);
        deal(address(weth), address(this), 2e18);
        IStakingPoolToken stakingPoolToken = IStakingPoolToken(selfLendingPod.lpStakingPool());

        uni_pair = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f).getPair(
            address(pair), address(selfLendingPod)
        );

        uint256 balance = IERC20(uni_pair).balanceOf(address(this));
        IERC20(uni_pair).approve(address(stakingPoolToken), type(uint256).max);
        stakingPoolToken.stake(address(this), balance);
        //IERC20(address(stakingPoolToken)).transfer(address(this), balance);

        ITokenRewards rewards = ITokenRewards(IStakingPoolToken(selfLendingPod.lpStakingPool()).POOL_REWARDS());

        IERC20(weth).approve(address(rewards), 1e18);
        rewards.depositRewards(weth, 1e18);
    }

    function _deploySelfLendingPod() internal {
        uint16 fee = 100;
        IDecentralizedIndex.Config memory _c;
        IDecentralizedIndex.Fees memory _f;
        _f.bond = fee;
        _f.debond = fee;
        address[] memory _t = new address[](1);
        _t[0] = address(DAI);
        uint256[] memory _w = new uint256[](1);
        _w[0] = 100;
        address _pod = _createPod(
            "Test",
            "pTEST",
            _c,
            _f,
            _t,
            _w,
            address(0),
            false,
            abi.encode(
                address(pair), // fDAI is the _pairedLPToken
                address(peas), // _lpRewardsToken
                0x6B175474E89094C44Da98b954EedeAC495271d0F, // _dai
                0x7d544DD34ABbE24C8832db27820Ff53C151e949b, // _feeRouter
                whitelister, // _rewardsWhitelister
                0x024ff47D552cB222b265D68C7aeB26E586D5229D, // _v3TwapUtils
                dexAdapter // _dexAdapter
            )
        );
        selfLendingPod = WeightedIndex(payable(_pod));
        vm.label(address(selfLendingPod), "SelfLendingPod");

        // mocking some liquidity in the pool
        // address uni_pair =
        //     IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f).getPair(address(DAI), address(selfLendingPod));
        // IUniswapV2Router02 router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

        //@e SEEDING INITIAL LIQ
        deal(address(DAI), address(this), 100000e18);
        DAI.approve(address(selfLendingPod), type(uint256).max);
        pair.approve(address(selfLendingPod), type(uint256).max);

        selfLendingPod.bond(address(DAI), 50_000e18, 0);
        selfLendingPod.addLiquidityV2(40_000e18, pair.balanceOf(address(this)), 1000, block.timestamp + 50);

        selfLending_spTkn = pod.lpStakingPool();
        selfLending_aspTkn = new AutoCompoundingPodLp(
            "self_aspTkn", "self_aspTkn", true, selfLendingPod, dexAdapter, IIndexUtils(address(idxUtils))
        );
    }

    function _deployFraxPairDeployer() internal {
        ConstructorParams memory _params =
            ConstructorParams(circuitBreaker, comptroller, timelock, address(_fraxWhitelist), address(_fraxRegistry));
        deployer = new FraxlendPairDeployer(_params);

        deployer.setCreationCode(type(FraxlendPair).creationCode);

        address[] memory _whitelistDeployer = new address[](1);
        _whitelistDeployer[0] = address(this);

        _fraxWhitelist.setFraxlendDeployerWhitelist(_whitelistDeployer, true);

        address[] memory _registryDeployer = new address[](1);
        _registryDeployer[0] = address(deployer);

        _fraxRegistry.setDeployers(_registryDeployer, true);
    }

    function _deployFraxPairRegistry() internal {
        address[] memory _initialDeployers = new address[](0);
        _fraxRegistry = new FraxlendPairRegistry(address(this), _initialDeployers);
    }

    function _deployFraxWhitelist() internal {
        _fraxWhitelist = new FraxlendWhitelist();
    }

    function _deployFraxPairs() internal {
        pair = FraxlendPair(
            deployer.deploy(
                abi.encode(
                    address(DAI), // asset
                    address(aspTkn), // collateral
                    oracle, //oracle
                    5000, // maxOracleDeviation
                    address(_variableInterestRate), //rateContract
                    1000, //fullUtilizationRate
                    75000, // maxLtv (75%)
                    10000, // uint256 _cleanLiquidationFee
                    9000, // uint256 _dirtyLiquidationFee
                    2000 //uint256 _protocolLiquidationFee
                )
            )
        );
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

    function _deployLendingAssetVault() internal {
        _lendingAssetVault = new LendingAssetVault("Test LAV", "tLAV", address(DAI));

        IERC20 vaultAsset1Peas = IERC20(pair.asset());
        vaultAsset1Peas.approve(address(pair), vaultAsset1Peas.totalSupply());
        vaultAsset1Peas.approve(address(_lendingAssetVault), vaultAsset1Peas.totalSupply());
        _lendingAssetVault.setVaultWhitelist(address(pair), true);

        // set external access vault for fraxLendingPair
        vm.prank(timelock);
        pair.setExternalAssetVault(IERC4626Extended(address(_lendingAssetVault)));

        address[] memory vaultAddresses = new address[](1);
        vaultAddresses[0] = address(pair);
        _lendingAssetVault.setVaultMaxAllocation(vaultAddresses, _fraxPercentages);
    }
}

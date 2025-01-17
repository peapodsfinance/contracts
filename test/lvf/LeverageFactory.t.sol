// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {IDecentralizedIndex} from "../../contracts/interfaces/IDecentralizedIndex.sol";
import {IIndexUtils} from "../../contracts/interfaces/IIndexUtils.sol";
import {IMinimalOracle} from "../../contracts/interfaces/IMinimalOracle.sol";
import {IndexUtils} from "../../contracts/IndexUtils.sol";
import {AutoCompoundingPodLpFactory} from "../../contracts/AutoCompoundingPodLpFactory.sol";
import {aspTKNMinimalOracleFactory} from "../../contracts/oracle/aspTKNMinimalOracleFactory.sol";
import {RewardsWhitelist} from "../../contracts/RewardsWhitelist.sol";
import {IndexManager} from "../../contracts/IndexManager.sol";
import {WeightedIndexFactory} from "../../contracts/WeightedIndexFactory.sol";
import {WeightedIndex} from "../../contracts/WeightedIndex.sol";
import {StakingPoolToken} from "../../contracts/StakingPoolToken.sol";
import {TokenRewards} from "../../contracts/TokenRewards.sol";
import {ChainlinkSinglePriceOracle} from "../../contracts/oracle/ChainlinkSinglePriceOracle.sol";
import {UniswapV3SinglePriceOracle} from "../../contracts/oracle/UniswapV3SinglePriceOracle.sol";
import {V2ReservesUniswap} from "../../contracts/oracle/V2ReservesUniswap.sol";
import {DIAOracleV2SinglePriceOracle} from "../../contracts/oracle/DIAOracleV2SinglePriceOracle.sol";
import {PEAS} from "../../contracts/PEAS.sol";
import {V3TwapUtilities} from "../../contracts/twaputils/V3TwapUtilities.sol";
import {UniswapDexAdapter} from "../../contracts/dex/UniswapDexAdapter.sol";
import {BalancerFlashSource} from "../../contracts/flash/BalancerFlashSource.sol";
import {LeverageManager} from "../../contracts/lvf/LeverageManager.sol";
import {LeverageFactory} from "../../contracts/lvf/LeverageFactory.sol";
import {MockFraxlendPairDeployer} from "../mocks/MockFraxlendPairDeployer.sol";
import {PodHelperTest} from "../helpers/PodHelper.t.sol";

contract LeverageFactoryTest is PodHelperTest {
    IIndexUtils public idxUtils;
    BalancerFlashSource public flashSource;
    LeverageManager public leverageManager;
    LeverageFactory public leverageFactory;
    MockFraxlendPairDeployer public mockFraxlendPairDeployer;
    PEAS public peas;
    V2ReservesUniswap public _v2Res;
    ChainlinkSinglePriceOracle public _clOracle;
    UniswapV3SinglePriceOracle public _uniOracle;
    DIAOracleV2SinglePriceOracle public _diaOracle;
    aspTKNMinimalOracleFactory public aspTknOracleFactory;
    AutoCompoundingPodLpFactory public aspTknFactory;
    RewardsWhitelist public whitelister;
    V3TwapUtilities public twapUtils;
    UniswapDexAdapter public dexAdapter;
    IndexManager public indexManager;
    WeightedIndexFactory public podFactory;
    WeightedIndex public pod;

    uint16 public fee;
    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public spTkn;
    address public peasClPool = 0xAe750560b09aD1F5246f3b279b3767AfD1D79160;

    address public constant ALICE = address(0x1);
    address public constant BOB = address(0x2);
    uint256 public constant INITIAL_BALANCE = 1000000 * 1e18;

    function setUp() public override {
        super.setUp();
        fee = 100;
        peas = PEAS(0x02f92800F57BCD74066F5709F1Daa1A4302Df875);
        _v2Res = new V2ReservesUniswap();
        _clOracle = new ChainlinkSinglePriceOracle(address(0));
        _uniOracle = new UniswapV3SinglePriceOracle(address(0));
        _diaOracle = new DIAOracleV2SinglePriceOracle(address(0));
        aspTknFactory = new AutoCompoundingPodLpFactory();
        aspTknFactory.setMinimumDepositAtCreation(0);
        aspTknOracleFactory = new aspTKNMinimalOracleFactory();
        podFactory = new WeightedIndexFactory();
        (address pi, address pb, address sti, address stb, address tri, address trb) = _deployPodBeacons();
        podFactory.setImplementationsAndBeacons(pi, sti, tri, pb, stb, trb);

        indexManager = new IndexManager(podFactory);
        whitelister = new RewardsWhitelist();
        twapUtils = new V3TwapUtilities();
        dexAdapter = new UniswapDexAdapter(
            twapUtils,
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, // Uniswap V2 Router
            0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45, // Uniswap SwapRouter02
            false
        );
        idxUtils = new IndexUtils(twapUtils, dexAdapter);
        IDecentralizedIndex.Config memory _c;
        IDecentralizedIndex.Fees memory _f;
        _f.bond = fee;
        _f.debond = fee;
        address[] memory _t = new address[](1);
        _t[0] = address(peas);
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
                dai,
                address(peas),
                dai,
                0x7d544DD34ABbE24C8832db27820Ff53C151e949b,
                whitelister,
                0x024ff47D552cB222b265D68C7aeB26E586D5229D,
                dexAdapter
            )
        );
        pod = WeightedIndex(payable(_pod));

        // Deploy MockFraxlendPairDeployer
        mockFraxlendPairDeployer = new MockFraxlendPairDeployer();

        // Deploy LeverageManager
        leverageManager = new LeverageManager("Leverage Position", "LP", idxUtils);
        flashSource = new BalancerFlashSource(address(leverageManager));

        // Setup LeverageManager
        // leverageManager.setLendingPair(address(pod), address(mockFraxlendPair));
        leverageManager.setFlashSource(dai, address(flashSource));

        leverageFactory = new LeverageFactory(
            address(indexManager),
            address(leverageManager),
            address(aspTknFactory),
            address(aspTknOracleFactory),
            address(mockFraxlendPairDeployer)
        );

        // set ownership of a couple CAs to leverage factory so the factory can make admin changes
        leverageManager.transferOwnership(address(leverageFactory));
        aspTknFactory.transferOwnership(address(leverageFactory));
        aspTknOracleFactory.transferOwnership(address(leverageFactory));

        // Approve LeverageManager to spend tokens
        vm.startPrank(ALICE);
        pod.approve(address(leverageManager), type(uint256).max);
        IERC20(dai).approve(address(leverageManager), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(BOB);
        pod.approve(address(leverageManager), type(uint256).max);
        IERC20(dai).approve(address(leverageManager), type(uint256).max);
        vm.stopPrank();
    }

    function test_transferContractOwnership() public {
        // this contract is the leverageFactory's owner, so we can call this
        // without reverting, and we can call it on the leverageManager
        // because the leverageFactory is the leverageManager's owner
        leverageFactory.transferContractOwnership(address(leverageManager), address(0x1));
        assertEq(leverageManager.owner(), address(0x1), "Ownership was not changed");
    }

    function test_addLvfSupportForPod() public {
        (,, address _fraxlendPair) = leverageFactory.addLvfSupportForPod(
            address(pod),
            address(dexAdapter),
            address(idxUtils),
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                dai,
                false,
                false,
                pod.lpStakingPool(),
                address(0) // mainClPool // TODO: determine if we need this for this test
            ),
            abi.encode(address(0), address(0), address(0), address(0), address(0), address(_v2Res)),
            // dummy data that is only needed for the fraxlend deployer mock
            abi.encode(uint32(0), address(0), uint64(0), uint256(0), uint256(0), uint256(0))
        );

        // add leverage without reverting
        uint256 pTknAmt = 100 * 1e18;
        uint256 pairedLpDesired = 50 * 1e18;
        bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

        // Supply borrow asset to pair
        deal(dai, address(this), 1e9 * 1e18);
        IERC20(dai).approve(_fraxlendPair, 1e9 * 1e18);
        IERC4626(_fraxlendPair).deposit(1e9 * 1e18, address(this));

        deal(address(peas), ALICE, pTknAmt * 100);

        vm.startPrank(ALICE);

        // wrap into the pod
        peas.approve(address(pod), peas.totalSupply());
        pod.bond(address(peas), pTknAmt, 0);

        uint256 positionId = leverageManager.initializePosition(address(pod), ALICE, address(0), false);

        uint256 alicePodTokenBalanceBefore = pod.balanceOf(ALICE);
        uint256 aliceAssetBalanceBefore = IERC20(dai).balanceOf(ALICE);

        leverageManager.addLeverage(positionId, address(pod), pTknAmt, pairedLpDesired, 0, false, config);

        vm.stopPrank();

        // Verify the position NFT was minted
        assertEq(leverageManager.positionNFT().ownerOf(positionId), ALICE, "Position NFT not minted to ALICE");

        // Verify the balance changes in the mock contracts
        assertEq(
            pod.balanceOf(ALICE),
            alicePodTokenBalanceBefore - pTknAmt,
            "Incorrect Pod Token balance after adding leverage"
        );
        assertEq(IERC20(dai).balanceOf(ALICE), aliceAssetBalanceBefore, "Asset balance should not change for ALICE");

        // Verify the state of the LeverageManager contract
        (address returnedPod, address lendingPair, address custodian, bool isSelfLending, bool hasSelfLendingPairPod) =
            leverageManager.positionProps(positionId);
        assertEq(returnedPod, address(pod), "Incorrect pod address");
        assertEq(lendingPair, address(_fraxlendPair), "Incorrect lending pair address");
        assertNotEq(custodian, address(0), "Custodian address should not be zero");
        assertEq(isSelfLending, false, "Not self lending");
        assertEq(hasSelfLendingPairPod, false, "Self lending pod should be zero");
    }

    function test_createSelfLendingPodAndAddLvf() public {
        IDecentralizedIndex.Config memory _c;
        IDecentralizedIndex.Fees memory _f;
        _f.bond = fee;
        _f.debond = fee;
        address[] memory _t = new address[](1);
        _t[0] = address(peas);
        uint256[] memory _w = new uint256[](1);
        _w[0] = 100;
        // console2.log("GAS1", gasleft());
        (address _selfLendingPod, address _aspTkn, address _aspTknOracle, address _fraxlendPair) = leverageFactory
            .createSelfLendingPodAndAddLvf(
            dai,
            address(dexAdapter),
            address(idxUtils),
            abi.encode(
                "Test",
                "pTEST",
                abi.encode(_c, _f, _t, _w, address(0), false),
                abi.encode(
                    dai,
                    address(peas),
                    dai,
                    0x7d544DD34ABbE24C8832db27820Ff53C151e949b,
                    whitelister,
                    0x024ff47D552cB222b265D68C7aeB26E586D5229D,
                    dexAdapter
                )
            ),
            abi.encode(
                address(_clOracle), address(_uniOracle), address(_diaOracle), dai, false, false, address(0), peasClPool
            ),
            abi.encode(address(0), address(0), address(0), address(0), address(0), address(_v2Res)),
            // dummy data that is only needed for the fraxlend deployer mock
            abi.encode(uint32(0), address(0), uint64(0), uint256(0), uint256(0), uint256(0))
        );
        // console2.log("GAS2", gasleft());

        // add leverage without reverting
        uint256 pTknAmt = 100 * 1e18;
        uint256 pairedLpDesired = 50 * 1e18;
        bytes memory config = abi.encode(0, 1000, block.timestamp + 1 hours);

        // Supply borrow asset to pair
        deal(dai, address(this), 1e9 * 1e18);
        IERC20(dai).approve(_fraxlendPair, 1e9 * 1e18);
        IERC4626(_fraxlendPair).deposit(1e9 * 1e18, address(this));

        deal(address(peas), ALICE, pTknAmt * 100);

        vm.startPrank(ALICE);

        // wrap into the pod
        peas.approve(_selfLendingPod, peas.totalSupply());
        IDecentralizedIndex(_selfLendingPod).bond(address(peas), pTknAmt, 0);

        uint256 positionId = leverageManager.initializePosition(_selfLendingPod, ALICE, _fraxlendPair, false);

        uint256 alicePodTokenBalanceBefore = IDecentralizedIndex(_selfLendingPod).balanceOf(ALICE);
        uint256 aliceAssetBalanceBefore = IERC20(dai).balanceOf(ALICE);

        IDecentralizedIndex(_selfLendingPod).approve(address(leverageManager), type(uint256).max);
        IERC20(dai).approve(address(leverageManager), type(uint256).max);

        leverageManager.addLeverage(positionId, _selfLendingPod, pTknAmt, pairedLpDesired, 0, false, config);

        vm.stopPrank();

        // Verify the position NFT was minted
        assertEq(leverageManager.positionNFT().ownerOf(positionId), ALICE, "Position NFT not minted to ALICE");

        // Verify the balance changes in the mock contracts
        assertEq(
            IDecentralizedIndex(_selfLendingPod).balanceOf(ALICE),
            alicePodTokenBalanceBefore - pTknAmt,
            "Incorrect Pod Token balance after adding leverage"
        );
        assertEq(IERC20(dai).balanceOf(ALICE), aliceAssetBalanceBefore, "Asset balance should not change for ALICE");

        // Verify the state of the LeverageManager contract
        (address returnedPod, address lendingPair, address custodian, bool isSelfLending,) =
            leverageManager.positionProps(positionId);
        assertEq(returnedPod, _selfLendingPod, "Incorrect pod address");
        assertEq(lendingPair, address(_fraxlendPair), "Incorrect lending pair address");
        assertNotEq(custodian, address(0), "Custodian address should not be zero");
        assertEq(isSelfLending, true, "Is self lending");
    }

    function _deployPodBeacons() internal returns (address, address, address, address, address, address) {
        WeightedIndex podImpl = new WeightedIndex();
        UpgradeableBeacon podBeacon = new UpgradeableBeacon(address(podImpl), address(this));
        StakingPoolToken spImpl = new StakingPoolToken();
        UpgradeableBeacon spBeacon = new UpgradeableBeacon(address(spImpl), address(this));
        TokenRewards rewardsImpl = new TokenRewards();
        UpgradeableBeacon rewardsBeacon = new UpgradeableBeacon(address(rewardsImpl), address(this));
        return (
            address(podImpl),
            address(podBeacon),
            address(spImpl),
            address(spBeacon),
            address(rewardsImpl),
            address(rewardsBeacon)
        );
    }
}

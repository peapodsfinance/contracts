// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {StakingPoolToken} from "../contracts/StakingPoolToken.sol";
import {TokenRewards} from "../contracts/TokenRewards.sol";
import {PEAS, IERC20} from "../contracts/PEAS.sol";
import {RewardsWhitelist} from "../contracts/RewardsWhitelist.sol";
import {V3TwapUtilities} from "../contracts/twaputils/V3TwapUtilities.sol";
import {UniswapDexAdapter} from "../contracts/dex/UniswapDexAdapter.sol";
import {IDecentralizedIndex} from "../contracts/interfaces/IDecentralizedIndex.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PodHelperTest} from "./helpers/PodHelper.t.sol";

contract StakingPoolTokenTest is PodHelperTest {
    StakingPoolToken public stakingPool;
    PEAS public peas;
    RewardsWhitelist public rewardsWhitelist;
    V3TwapUtilities public v3TwapUtils;
    UniswapDexAdapter public dexAdapter;
    IERC20 public stakingToken;
    TokenRewards public poolRewards;

    address public owner;
    address public user1;
    address public user2;
    address public indexFund;

    address public dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    uint16 fee = 100;

    function setUp() public override {
        super.setUp();
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        peas = PEAS(0x02f92800F57BCD74066F5709F1Daa1A4302Df875);
        v3TwapUtils = new V3TwapUtilities();
        rewardsWhitelist = new RewardsWhitelist();
        dexAdapter = new UniswapDexAdapter(
            v3TwapUtils,
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, // Uniswap V2 Router
            0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45, // Uniswap SwapRouter02
            false
        );
        (address _indexFund, address _stakingPool, address _stakingToken, address _poolRewards) = _createPodAndReturn();
        indexFund = _indexFund;
        stakingPool = StakingPoolToken(_stakingPool);
        stakingToken = IERC20(_stakingToken);
        poolRewards = TokenRewards(_poolRewards);

        // Fund users
        deal(address(stakingToken), user1, 1000e18);
        deal(address(stakingToken), user2, 1000e18);
        vm.startPrank(user1);
        stakingToken.approve(address(stakingPool), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(user2);
        stakingToken.approve(address(stakingPool), type(uint256).max);
        vm.stopPrank();
    }

    function test_initialize() public {
        (address _indexFund, address _newPool,,) = _createPodAndReturn();
        StakingPoolToken newPool = StakingPoolToken(_newPool);

        assertEq(newPool.INDEX_FUND(), _indexFund, "indexFund");
        assertEq(newPool.stakeUserRestriction(), address(0), "stakeUserRestriction");
        assertEq(address(newPool.DEX_ADAPTER()), address(dexAdapter), "dexAdapter");
        assertEq(address(newPool.V3_TWAP_UTILS()), address(v3TwapUtils), "v3TwapUtils");
    }

    function test_initializeSelector() public view {
        bytes4 selector = stakingPool.initializeSelector();
        assertEq(selector, stakingPool.initialize.selector);
    }

    function test_stake() public {
        uint256 stakeAmount = 100e18;
        vm.startPrank(user1);
        stakingPool.stake(user1, stakeAmount);
        vm.stopPrank();

        assertEq(stakingPool.balanceOf(user1), stakeAmount);
        assertEq(stakingToken.balanceOf(address(stakingPool)), stakeAmount);
        assertEq(poolRewards.shares(user1), stakeAmount);
    }

    function test_stake_withRestriction() public {
        uint256 stakeAmount = 100e18;

        // Set restriction to user1
        vm.startPrank(address(0));
        stakingPool.setStakeUserRestriction(user1);
        vm.stopPrank();

        // Should succeed for user1
        vm.startPrank(user1);
        stakingPool.stake(user1, stakeAmount);
        vm.stopPrank();

        // Should fail for user2
        vm.startPrank(user2);
        vm.expectRevert();
        stakingPool.stake(user2, stakeAmount);
        vm.stopPrank();
    }

    function test_unstake() public {
        uint256 stakeAmount = 100e18;

        // First stake
        vm.startPrank(user1);
        stakingPool.stake(user1, stakeAmount);

        // Then unstake
        stakingPool.unstake(stakeAmount);
        vm.stopPrank();

        assertEq(stakingPool.balanceOf(user1), 0);
        assertEq(stakingToken.balanceOf(user1), 1000e18);
        assertEq(poolRewards.shares(user1), 0);
    }

    // function test_setPoolRewards() public {
    //     StakingPoolToken newPool = new StakingPoolToken();
    //     bytes memory immutables = abi.encode(
    //         address(0), address(0), address(0), address(0), address(0), address(v3TwapUtils), address(dexAdapter)
    //     );

    //     // Set block number before any contract operations
    //     uint256 initBlock = 200;
    //     vm.roll(initBlock);

    //     // Deploy and initialize contract in same block
    //     vm.startPrank(owner);
    //     newPool.initialize("New Pool", "NPT", indexFund, address(0), immutables);

    //     address newRewards = makeAddr("newRewards");
    //     newPool.setPoolRewards(newRewards);
    //     vm.stopPrank();

    //     // Move to next block for remaining tests
    //     vm.roll(initBlock + 1);
    //     assertEq(newPool.POOL_REWARDS(), newRewards);

    //     // Should fail on second attempt in same block
    //     vm.expectRevert();
    //     newPool.setPoolRewards(address(0));

    //     // Should fail if trying to set in a different block
    //     vm.roll(block.number + 1);
    //     vm.expectRevert();
    //     newPool.setPoolRewards(address(0));
    // }

    // function test_setStakingToken() public {
    //     StakingPoolToken newPool = new StakingPoolToken();
    //     bytes memory immutables = abi.encode(
    //         address(0), address(0), address(0), address(0), address(0), address(v3TwapUtils), address(dexAdapter)
    //     );

    //     newPool.initialize("New Pool", "NPT", indexFund, address(0), immutables);

    //     address newToken = makeAddr("newToken");
    //     newPool.setStakingToken(newToken);
    //     assertEq(newPool.stakingToken(), newToken);

    //     // Should fail on second attempt
    //     vm.expectRevert();
    //     newPool.setStakingToken(address(0));
    // }

    function test_removeStakeUserRestriction() public {
        // Set initial restriction
        vm.startPrank(address(0));
        stakingPool.setStakeUserRestriction(user1);
        vm.stopPrank();
        assertEq(stakingPool.stakeUserRestriction(), user1);

        // Remove restriction
        vm.startPrank(user1);
        stakingPool.removeStakeUserRestriction();
        vm.stopPrank();
        assertEq(stakingPool.stakeUserRestriction(), address(0));
    }

    function test_setStakeUserRestriction() public {
        vm.startPrank(address(0));
        stakingPool.setStakeUserRestriction(user1);
        vm.stopPrank();
        assertEq(stakingPool.stakeUserRestriction(), user1);

        vm.startPrank(user1);
        stakingPool.setStakeUserRestriction(user2);
        vm.stopPrank();
        assertEq(stakingPool.stakeUserRestriction(), user2);
    }

    function test_RevertWhen_UnauthorizedSetStakeUserRestriction() public {
        vm.startPrank(user1);
        vm.expectRevert();
        stakingPool.setStakeUserRestriction(user2);
        vm.stopPrank();
    }

    function test_RevertWhen_UnauthorizedRemoveStakeUserRestriction() public {
        vm.startPrank(user1);
        vm.expectRevert();
        stakingPool.removeStakeUserRestriction();
        vm.stopPrank();
    }

    // function test_RevertWhen_StakeWithoutStakingToken() public {
    //     StakingPoolToken newPool = new StakingPoolToken();
    //     bytes memory immutables = abi.encode(
    //         address(0), address(0), address(0), address(0), address(0), address(v3TwapUtils), address(dexAdapter)
    //     );

    //     newPool.initialize("New Pool", "NPT", indexFund, address(0), immutables);

    //     vm.prank(user1);
    //     vm.expectRevert();
    //     newPool.stake(user1, 100e18);
    // }

    function test_transfer_updatesShares() public {
        uint256 stakeAmount = 100e18;
        uint256 transferAmount = 40e18;

        // First stake
        vm.prank(user1);
        stakingPool.stake(user1, stakeAmount);
        assertEq(poolRewards.shares(user1), stakeAmount);

        // Transfer some tokens
        vm.prank(user1);
        stakingPool.transfer(user2, transferAmount);

        // Check shares are updated correctly
        assertEq(poolRewards.shares(user1), stakeAmount - transferAmount);
        assertEq(poolRewards.shares(user2), transferAmount);
    }

    function test_transferFrom_updatesShares() public {
        uint256 stakeAmount = 100e18;
        uint256 transferAmount = 40e18;

        // First stake
        vm.prank(user1);
        stakingPool.stake(user1, stakeAmount);

        // Approve transfer
        vm.prank(user1);
        stakingPool.approve(user2, transferAmount);

        // Transfer using transferFrom
        vm.prank(user2);
        stakingPool.transferFrom(user1, user2, transferAmount);

        // Check shares are updated correctly
        assertEq(poolRewards.shares(user1), stakeAmount - transferAmount);
        assertEq(poolRewards.shares(user2), transferAmount);
    }

    function test_burn_updatesShares() public {
        uint256 stakeAmount = 100e18;
        uint256 burnAmount = 40e18;

        // First stake
        vm.prank(user1);
        stakingPool.stake(user1, stakeAmount);

        // Burn tokens
        vm.prank(user1);
        stakingPool.unstake(burnAmount);

        // Check shares are updated correctly
        assertEq(poolRewards.shares(user1), stakeAmount - burnAmount);
    }

    function _createPodAndReturn()
        internal
        returns (address _indexFund, address _stakingPool, address _stakingToken, address _tokenRewards)
    {
        IDecentralizedIndex.Config memory _c;
        IDecentralizedIndex.Fees memory _f;
        _f.bond = fee;
        _f.debond = fee;
        address[] memory _t = new address[](1);
        _t[0] = address(peas);
        uint256[] memory _w = new uint256[](1);
        _w[0] = 100;
        _indexFund = _createPod(
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
                0x6B175474E89094C44Da98b954EedeAC495271d0F,
                0x7d544DD34ABbE24C8832db27820Ff53C151e949b,
                rewardsWhitelist,
                address(v3TwapUtils),
                dexAdapter
            )
        );
        _stakingPool = IDecentralizedIndex(payable(_indexFund)).lpStakingPool();
        _stakingToken = StakingPoolToken(_stakingPool).stakingToken();
        _tokenRewards = StakingPoolToken(_stakingPool).POOL_REWARDS();
    }
}

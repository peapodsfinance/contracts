// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/voting/VotingPool.sol";
import "../../contracts/interfaces/IProtocolFeeRouter.sol";
import "../../contracts/interfaces/IRewardsWhitelister.sol";
import "../../contracts/interfaces/IDexAdapter.sol";
import "../../contracts/interfaces/IV3TwapUtilities.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PodHelperTest} from "../helpers/PodHelper.t.sol";

contract VotingPoolTest is PodHelperTest {
    VotingPool public votingPool;
    MockERC20 public pairedLpToken;
    MockERC20 public rewardsToken;
    MockProtocolFeeRouter public mockFeeRouter;
    MockRewardsWhitelister public mockRewardsWhitelister;
    MockDexAdapter public mockDexAdapter;
    MockV3TwapUtilities public mockV3TwapUtilities;
    address public alice = address(0x1);
    address public bob = address(0x2);
    uint256 public constant INITIAL_BALANCE = 1000 * 1e18;

    function setUp() public override {
        super.setUp();
        pairedLpToken = new MockERC20("Paired LP Token", "PLP");
        rewardsToken = new MockERC20("Reward Token", "RWD");
        mockFeeRouter = new MockProtocolFeeRouter();
        mockRewardsWhitelister = new MockRewardsWhitelister();
        mockDexAdapter = new MockDexAdapter();
        mockV3TwapUtilities = new MockV3TwapUtilities();

        (,, address tokenRewardsImpl,,, address tokenRewardsBeacon) = _podDeployerSub.deployedContracts();

        votingPool = new VotingPool(
            tokenRewardsBeacon,
            tokenRewardsImpl,
            abi.encode(
                address(pairedLpToken),
                address(rewardsToken),
                address(pairedLpToken),
                address(mockFeeRouter),
                address(mockRewardsWhitelister),
                address(mockV3TwapUtilities),
                address(mockDexAdapter)
            )
        );

        // Mint initial balances
        pairedLpToken.mint(alice, INITIAL_BALANCE);
        pairedLpToken.mint(bob, INITIAL_BALANCE);

        // Approve spending for alice and bob
        vm.prank(alice);
        pairedLpToken.approve(address(votingPool), type(uint256).max);
        vm.prank(bob);
        pairedLpToken.approve(address(votingPool), type(uint256).max);

        // Enable pairedLpToken as a staking asset
        votingPool.addOrUpdateAsset(address(pairedLpToken), IStakingConversionFactor(address(0)), true);
    }

    function testStake() public {
        uint256 stakeAmount = 100 * 1e18;

        vm.prank(alice);
        votingPool.stake(address(pairedLpToken), stakeAmount);

        assertEq(votingPool.balanceOf(alice), stakeAmount, "Staked balance should match");
        assertEq(pairedLpToken.balanceOf(alice), INITIAL_BALANCE - stakeAmount, "Token balance should decrease");
        assertEq(pairedLpToken.balanceOf(address(votingPool)), stakeAmount, "VotingPool should hold staked tokens");
    }

    function testStakeZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(bytes("A"));
        votingPool.stake(address(pairedLpToken), 0);
    }

    function testUnstakeBeforeLockupPeriod() public {
        uint256 stakeAmount = 100 * 1e18;

        vm.startPrank(alice);
        votingPool.stake(address(pairedLpToken), stakeAmount);

        vm.expectRevert(bytes("LU"));
        votingPool.unstake(address(pairedLpToken), stakeAmount);
        vm.stopPrank();
    }

    function testUnstakeAfterLockupPeriod() public {
        uint256 stakeAmount = 100 * 1e18;

        vm.startPrank(alice);
        votingPool.stake(address(pairedLpToken), stakeAmount);

        // Fast forward time to after the lockup period
        vm.warp(block.timestamp + votingPool.lockupPeriod() + 1);

        votingPool.unstake(address(pairedLpToken), stakeAmount);
        vm.stopPrank();

        assertEq(votingPool.balanceOf(alice), 0, "Staked balance should be zero");
        assertEq(pairedLpToken.balanceOf(alice), INITIAL_BALANCE, "Token balance should be restored");
    }

    function testMultipleUsersStakeUnstake() public {
        uint256 aliceStake = 100 * 1e18;
        uint256 bobStake = 150 * 1e18;

        vm.prank(alice);
        votingPool.stake(address(pairedLpToken), aliceStake);

        vm.prank(bob);
        votingPool.stake(address(pairedLpToken), bobStake);

        assertEq(votingPool.balanceOf(alice), aliceStake, "Alice's staked balance should match");
        assertEq(votingPool.balanceOf(bob), bobStake, "Bob's staked balance should match");

        // Fast forward time to after the lockup period
        vm.warp(block.timestamp + votingPool.lockupPeriod() + 1);

        vm.prank(alice);
        votingPool.unstake(address(pairedLpToken), aliceStake);

        vm.prank(bob);
        votingPool.unstake(address(pairedLpToken), bobStake);

        assertEq(votingPool.balanceOf(alice), 0, "Alice's staked balance should be zero");
        assertEq(votingPool.balanceOf(bob), 0, "Bob's staked balance should be zero");
        assertEq(pairedLpToken.balanceOf(address(votingPool)), 0, "VotingPool balance should be zero");
    }
}

// Mock contracts
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract MockProtocolFeeRouter {
    function getProtocolFee(address) external pure virtual returns (uint256) {
        return 0;
    }
}

contract MockRewardsWhitelister {
    function getFullWhitelist() external pure virtual returns (address[] memory) {
        return new address[](0);
    }

    function whitelist(address) external pure virtual returns (bool) {
        return true;
    }

    function paused(address) external pure virtual returns (bool) {
        return false;
    }
}

contract MockDexAdapter {
    function swapV3Single(address, address, uint24, uint256, uint256, address)
        external
        pure
        virtual
        returns (uint256)
    {
        return 0;
    }

    function swapV2Single(address, address, uint256, uint256, address) external pure virtual returns (uint256) {
        return 0;
    }

    function getV3Pool(address, address, uint24) external pure virtual returns (address) {
        return address(0);
    }
}

contract MockV3TwapUtilities {
    function sqrtPriceX96FromPoolAndInterval(address) external pure virtual returns (uint160) {
        return 0;
    }

    function priceX96FromSqrtPriceX96(uint160) external pure virtual returns (uint256) {
        return 0;
    }
}

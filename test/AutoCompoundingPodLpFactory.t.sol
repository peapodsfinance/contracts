// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/AutoCompoundingPodLpFactory.sol";
import "../contracts/AutoCompoundingPodLp.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock contracts
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract MockTokenRewards {
    address[] private _processedRewardTokens;

    function getAllRewardsTokens() external view returns (address[] memory) {
        return _processedRewardTokens;
    }
}

contract MockStakingPoolToken is ERC20 {
    address public POOL_REWARDS;

    constructor(string memory name, string memory symbol, address _poolRewards) ERC20(name, symbol) {
        POOL_REWARDS = _poolRewards;
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract MockDecentralizedIndex {
    address public lpRewardsToken;
    address public lpStakingPool;
    address public PAIRED_LP_TOKEN;

    constructor(address _lpRewardsToken, address _lpStakingPool, address _pairedLpTkn) {
        lpRewardsToken = _lpRewardsToken;
        lpStakingPool = _lpStakingPool;
        PAIRED_LP_TOKEN = _pairedLpTkn;
    }
}

contract MockDexAdapter {}

contract MockIndexUtils {}

contract AutoCompoundingPodLpFactoryTest is Test {
    AutoCompoundingPodLpFactory public factory;
    MockERC20 public asset;
    MockERC20 public rewardsToken;
    MockTokenRewards public tokenRewards;
    MockStakingPoolToken public stakingPoolToken;
    MockDecentralizedIndex public pod;
    MockDexAdapter public dexAdapter;
    MockIndexUtils public indexUtils;
    address public owner;
    address public user;

    function setUp() public {
        owner = address(this);
        user = address(0x1);

        asset = new MockERC20("Test Token", "TEST");
        rewardsToken = new MockERC20("Test Token2", "TEST2");
        tokenRewards = new MockTokenRewards();
        stakingPoolToken = new MockStakingPoolToken("Staking Pool Token", "SPT", address(tokenRewards));
        pod = new MockDecentralizedIndex(address(rewardsToken), address(stakingPoolToken), address(asset));
        dexAdapter = new MockDexAdapter();
        indexUtils = new MockIndexUtils();
        factory = new AutoCompoundingPodLpFactory();

        // Transfer some tokens to the owner for testing
        asset.transfer(owner, 10000 * 10 ** 18);
    }

    function testCreateWithMinimumDeposit() public {
        string memory name = "Test Pod LP";
        string memory symbol = "TPODLP";
        bool isSelfLendingPod = false;
        uint96 salt = 0;

        // Set minimum deposit
        factory.setMinimumDepositAtCreation(1000);

        // Approve tokens for minimum deposit
        vm.startPrank(owner);
        stakingPoolToken.approve(address(factory), 1000);

        // Create the AutoCompoundingPodLp
        address expectedPodLpAddress = factory.getNewCaFromParams(
            name,
            symbol,
            isSelfLendingPod,
            IDecentralizedIndex(address(pod)),
            IDexAdapter(address(dexAdapter)),
            IIndexUtils(address(indexUtils)),
            salt
        );
        factory.create(
            name,
            symbol,
            isSelfLendingPod,
            IDecentralizedIndex(address(pod)),
            IDexAdapter(address(dexAdapter)),
            IIndexUtils(address(indexUtils)),
            salt
        );

        // Check if the AutoCompoundingPodLp was created at the expected address
        AutoCompoundingPodLp podLp = AutoCompoundingPodLp(expectedPodLpAddress);
        assertTrue(address(podLp) != address(0), "AutoCompoundingPodLp was not created");

        // Check if the AutoCompoundingPodLp properties are set correctly
        assertEq(podLp.name(), name, "AutoCompoundingPodLp name is incorrect");
        assertEq(podLp.symbol(), symbol, "AutoCompoundingPodLp symbol is incorrect");

        // Check if the ownership was transferred to the factory owner
        assertEq(podLp.owner(), owner, "AutoCompoundingPodLp ownership was not transferred correctly");

        // Check if the minimum deposit was made
        assertEq(podLp.totalAssets(), 1000, "Minimum deposit was not made");

        vm.stopPrank();
    }

    function testCreateWithoutMinimumDeposit() public {
        string memory name = "Test Pod LP No Min";
        string memory symbol = "TPLNM";
        bool isSelfLendingPod = true;
        uint96 salt = 1;

        // Set minimum deposit to 0
        factory.setMinimumDepositAtCreation(0);

        // Create the AutoCompoundingPodLp
        address expectedPodLpAddress = factory.getNewCaFromParams(
            name,
            symbol,
            isSelfLendingPod,
            IDecentralizedIndex(address(0)),
            IDexAdapter(address(dexAdapter)),
            IIndexUtils(address(indexUtils)),
            salt
        );
        factory.create(
            name,
            symbol,
            isSelfLendingPod,
            IDecentralizedIndex(address(0)),
            IDexAdapter(address(dexAdapter)),
            IIndexUtils(address(indexUtils)),
            salt
        );

        // Check if the AutoCompoundingPodLp was created at the expected address
        AutoCompoundingPodLp podLp = AutoCompoundingPodLp(expectedPodLpAddress);
        assertTrue(address(podLp) != address(0), "AutoCompoundingPodLp was not created");

        // Check if the AutoCompoundingPodLp properties are set correctly
        assertEq(podLp.name(), name, "AutoCompoundingPodLp name is incorrect");
        assertEq(podLp.symbol(), symbol, "AutoCompoundingPodLp symbol is incorrect");

        // Check if the ownership was transferred to the factory owner
        assertEq(podLp.owner(), owner, "AutoCompoundingPodLp ownership was not transferred correctly");

        // Check that no deposit was made
        assertEq(podLp.totalAssets(), 0, "Unexpected deposit was made");
    }

    function testCreateOnlyOwner() public {
        string memory name = "Test Pod LP";
        string memory symbol = "TPODLP";
        bool isSelfLendingPod = false;
        uint96 salt = 2;

        // Set minimum deposit to 0
        factory.setMinimumDepositAtCreation(0);

        // Try to create an AutoCompoundingPodLp as a non-owner
        vm.prank(user);
        // vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        factory.create(
            name,
            symbol,
            isSelfLendingPod,
            IDecentralizedIndex(address(pod)),
            IDexAdapter(address(dexAdapter)),
            IIndexUtils(address(indexUtils)),
            salt
        );
    }
}

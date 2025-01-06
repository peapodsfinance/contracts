// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/BulkPodYieldProcess.sol";
import "./mocks/MockERC20.sol";
import "../contracts/interfaces/IDecentralizedIndex.sol";
import "../contracts/interfaces/IStakingPoolToken.sol";
import "../contracts/interfaces/ITokenRewards.sol";

contract MockStakingPoolToken is IStakingPoolToken {
    address public override POOL_REWARDS;
    address public override INDEX_FUND;

    constructor(address poolRewards) {
        POOL_REWARDS = poolRewards;
        INDEX_FUND = address(this);
    }

    function initializeSelector() external pure returns (bytes4) {
        return bytes4(0);
    }

    function stakingToken() external pure returns (address) {
        return address(0);
    }

    function stakeUserRestriction() external pure returns (address) {
        return address(0);
    }

    function stake(address, uint256) external pure {}
    function unstake(uint256) external pure {}
    function setStakeUserRestriction(address) external pure {}
    function removeStakeUserRestriction() external pure {}
    function setPoolRewards(address) external pure {}
    function setStakingToken(address) external pure {}
}

contract MockTokenRewards is ITokenRewards {
    function depositFromPairedLpToken(uint256) external pure {}

    function rewardsToken() external pure returns (address) {
        return address(0);
    }

    function shares(address) external pure returns (uint256) {
        return 0;
    }

    function totalShares() external pure returns (uint256) {
        return 0;
    }

    function rewardPerShare() external pure returns (uint256) {
        return 0;
    }

    function userRewardPerSharePaid(address) external pure returns (uint256) {
        return 0;
    }

    function rewards(address) external pure returns (uint256) {
        return 0;
    }

    function earned(address) external pure returns (uint256) {
        return 0;
    }

    function getReward() external pure {}
    function notifyRewardAmount(uint256) external pure {}
    function setRewardsDuration(uint256) external pure {}
    function setRewardRate(uint256) external pure {}

    function rewardRate() external pure returns (uint256) {
        return 0;
    }

    function rewardsDuration() external pure returns (uint256) {
        return 0;
    }

    function periodFinish() external pure returns (uint256) {
        return 0;
    }

    function lastUpdateTime() external pure returns (uint256) {
        return 0;
    }

    function claimReward(address) external pure {}
    function depositRewards(address, uint256) external pure {}
    function depositRewardsNoTransfer(address, uint256) external pure {}

    function getAllRewardsTokens() external pure returns (address[] memory) {
        return new address[](0);
    }

    function setShares(address, uint256, bool) external pure {}

    function totalStakers() external pure returns (uint256) {
        return 0;
    }

    function trackingToken() external pure returns (address) {
        return address(0);
    }
}

contract MockDecentralizedIndex is IDecentralizedIndex {
    address public override lpStakingPool;

    constructor(address _lpStakingPool) {
        lpStakingPool = _lpStakingPool;
    }

    function initialize(
        string memory,
        string memory,
        Config memory,
        Fees memory,
        address[] memory,
        uint256[] memory,
        address,
        bool,
        bytes memory
    ) external pure {}

    function initializeSelector() external pure returns (bytes4) {
        return bytes4(0);
    }

    function name() external pure returns (string memory) {
        return "";
    }

    function symbol() external pure returns (string memory) {
        return "";
    }

    function decimals() external pure returns (uint8) {
        return 0;
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }

    function BOND_FEE() external pure returns (uint16) {
        return 0;
    }

    function DEBOND_FEE() external pure returns (uint16) {
        return 0;
    }

    function DEX_HANDLER() external pure returns (IDexAdapter) {
        return IDexAdapter(address(0));
    }

    function FLASH_FEE_AMOUNT_DAI() external pure returns (uint256) {
        return 0;
    }

    function PAIRED_LP_TOKEN() external pure returns (address) {
        return address(0);
    }

    function config() external pure returns (Config memory) {
        return Config(address(0), 0, false, false);
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

    function lpRewardsToken() external pure returns (address) {
        return address(0);
    }

    function partner() external pure returns (address) {
        return address(0);
    }

    function isAsset(address) external pure returns (bool) {
        return false;
    }

    function getAllAssets() external pure returns (IndexAssetInfo[] memory) {
        return new IndexAssetInfo[](0);
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

    function convertToAssets(uint256) external pure returns (uint256) {
        return 0;
    }

    function setup() external pure {}
    function bond(address, uint256, uint256) external pure {}
    function debond(uint256, address[] memory, uint8[] memory) external pure {}

    function addLiquidityV2(uint256, uint256, uint256, uint256) external pure returns (uint256) {
        return 0;
    }

    function removeLiquidityV2(uint256, uint256, uint256, uint256) external pure {}
    function flash(address, address, uint256, bytes calldata) external pure {}
    function flashMint(address, uint256, bytes calldata) external pure {}
    function setLpStakingPool(address) external pure {}

    function unlocked() external pure returns (uint8) {
        return 0;
    }
}

contract BulkPodYieldProcessTest is Test {
    BulkPodYieldProcess public processor;
    MockERC20[] public tokens;
    MockDecentralizedIndex[] public indices;
    address[] public stakingPools;
    address[] public poolRewards;

    function setUp() public {
        processor = new BulkPodYieldProcess();

        // Create mock tokens
        for (uint256 i = 0; i < 3; i++) {
            tokens.push(new MockERC20("Token", "TKN"));
        }

        // Create mock rewards and staking pools
        for (uint256 i = 0; i < 3; i++) {
            address rewards = address(new MockTokenRewards());
            poolRewards.push(rewards);
            address stakingPool = address(new MockStakingPoolToken(rewards));
            stakingPools.push(stakingPool);
            indices.push(new MockDecentralizedIndex(stakingPool));
        }
    }

    function test_bulkTransferEmpty() public {
        IERC20[] memory tokenArray = new IERC20[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenArray[i] = IERC20(address(tokens[i]));
        }

        // Should execute without reverting
        processor.bulkTransferEmpty(tokenArray);

        // Verify no actual tokens were transferred
        for (uint256 i = 0; i < tokens.length; i++) {
            assertEq(tokens[i].balanceOf(address(processor)), 0);
        }
    }

    function test_bulkProcessPendingYield() public {
        IDecentralizedIndex[] memory idxArray = new IDecentralizedIndex[](indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            idxArray[i] = indices[i];
        }

        // Should execute without reverting
        processor.bulkProcessPendingYield(idxArray);

        // Verify each index's staking pool and rewards were accessed correctly
        for (uint256 i = 0; i < indices.length; i++) {
            assertEq(indices[i].lpStakingPool(), stakingPools[i]);
            assertEq(MockStakingPoolToken(stakingPools[i]).POOL_REWARDS(), poolRewards[i]);
        }
    }

    function test_bulkTransferEmpty_emptyArray() public {
        IERC20[] memory emptyArray = new IERC20[](0);

        // Should execute without reverting with empty array
        processor.bulkTransferEmpty(emptyArray);
    }

    function test_bulkProcessPendingYield_emptyArray() public {
        IDecentralizedIndex[] memory emptyArray = new IDecentralizedIndex[](0);

        // Should execute without reverting with empty array
        processor.bulkProcessPendingYield(emptyArray);
    }
}

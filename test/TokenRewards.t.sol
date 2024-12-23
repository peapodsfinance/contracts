// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/TokenRewards.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract TokenRewardsExposed is TokenRewards {
    function exposedCumulativeRewards(address _token, uint256 _share, bool _roundUp) public view returns (uint256) {
        return _cumulativeRewards(_token, _share, _roundUp);
    }

    function setRewardsPerShare(address _token, uint256 _amount) public {
        _rewardsPerShare[_token] = _amount;
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // function burn(uint256 amount) public {
    //     _burn(msg.sender, amount);
    // }
}

contract MockProtocolFeeRouter {
    function protocolFees() public pure returns (IProtocolFees) {
        return IProtocolFees(address(0));
    }
}

contract MockRewardsWhitelister {
    bool private _paused;
    mapping(address => bool) private _whitelist;

    function whitelist(address token) public view returns (bool) {
        return _whitelist[token];
    }

    function setWhitelist(address token, bool status) public {
        _whitelist[token] = status;
    }

    function paused(address) public view returns (bool) {
        return _paused;
    }

    function setPaused(bool paused_) public {
        _paused = paused_;
    }
}

contract MockDexAdapter {
    function getV3Pool(address, address, uint24) public pure returns (address) {
        return address(0);
    }

    function swapV3Single(address, address, uint24, uint256, uint256, address) public pure {}
}

contract MockV3TwapUtilities {
    function sqrtPriceX96FromPoolAndInterval(address) public pure returns (uint160) {
        return 0;
    }

    function priceX96FromSqrtPriceX96(uint160) public pure returns (uint256) {
        return 0;
    }
}

contract TokenRewardsTest is Test {
    TokenRewardsExposed public implementation;
    TokenRewardsExposed public tokenRewards;
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;

    MockERC20 public pairedToken;
    MockERC20 public rewardsToken;
    MockERC20 public secondaryRewardToken;
    MockERC20 public trackingToken;
    MockProtocolFeeRouter public feeRouter;
    MockRewardsWhitelister public rewardsWhitelister;
    MockDexAdapter public dexAdapter;
    MockV3TwapUtilities public v3TwapUtilities;
    address public user1;
    address public user2;

    uint256 constant PRECISION = 10 ** 27;

    function setUp() public {
        user1 = address(0x1);
        user2 = address(0x2);

        pairedToken = new MockERC20("Paired LP Token", "PLP");
        rewardsToken = new MockERC20("Rewards Token", "RWD");
        secondaryRewardToken = new MockERC20("Secondary Reward Token", "SRT");
        trackingToken = new MockERC20("Tracking Token", "TRK");
        feeRouter = new MockProtocolFeeRouter();
        rewardsWhitelister = new MockRewardsWhitelister();
        dexAdapter = new MockDexAdapter();
        v3TwapUtilities = new MockV3TwapUtilities();

        // Deploy implementation
        implementation = new TokenRewardsExposed();

        // Setup proxy admin
        proxyAdmin = new ProxyAdmin(address(this));

        // Create initialization data
        bytes memory initData = abi.encodeWithSelector(
            TokenRewards.initialize.selector,
            address(this),
            address(trackingToken),
            false,
            abi.encode(
                address(pairedToken),
                address(rewardsToken),
                address(pairedToken),
                address(feeRouter),
                address(rewardsWhitelister),
                address(v3TwapUtilities),
                address(dexAdapter)
            )
        );

        // Deploy and initialize proxy
        proxy = new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);
        tokenRewards = TokenRewardsExposed(address(proxy));

        // Setup initial token amounts
        rewardsToken.mint(address(this), 1000e18);
        rewardsToken.approve(address(tokenRewards), type(uint256).max);
        secondaryRewardToken.mint(address(this), 1000e18);
        secondaryRewardToken.approve(address(tokenRewards), type(uint256).max);
        pairedToken.mint(address(this), 1000e18);
        pairedToken.approve(address(tokenRewards), type(uint256).max);
    }

    function processPreSwapFeesAndSwap() external {
        // NOOP
    }

    function testInitialization() public view {
        assertEq(tokenRewards.trackingToken(), address(trackingToken), "Tracking token not set correctly");
        assertEq(tokenRewards.rewardsToken(), address(rewardsToken), "Rewards token not set correctly");
        assertEq(tokenRewards.totalShares(), 0, "Initial total shares should be 0");
        assertEq(tokenRewards.totalStakers(), 0, "Initial total stakers should be 0");
    }

    // function testCannotReinitialize() public {
    //     bytes memory immutables = abi.encode(
    //         address(pairedToken),
    //         address(rewardsToken),
    //         address(pairedToken),
    //         address(feeRouter),
    //         address(rewardsWhitelister),
    //         address(v3TwapUtilities),
    //         address(dexAdapter)
    //     );

    //     vm.expectRevert(
    //         bytes("Initializable: contract is already initialized")
    //     );
    //     tokenRewards.initialize(
    //         address(this),
    //         address(trackingToken),
    //         false,
    //         immutables
    //     );
    // }

    function testSetShares() public {
        // Only tracking token can set shares
        vm.expectRevert(bytes("UNAUTHORIZED"));
        tokenRewards.setShares(user1, 100e18, false);

        // Set shares as tracking token
        vm.prank(address(trackingToken));
        tokenRewards.setShares(user1, 100e18, false);

        assertEq(tokenRewards.shares(user1), 100e18, "Shares not set correctly");
        assertEq(tokenRewards.totalShares(), 100e18, "Total shares not updated");
        assertEq(tokenRewards.totalStakers(), 1, "Total stakers not updated");
    }

    function testRemoveShares() public {
        // Add shares first
        vm.startPrank(address(trackingToken));
        tokenRewards.setShares(user1, 100e18, false);

        // Remove shares
        tokenRewards.setShares(user1, 50e18, true);
        vm.stopPrank();

        assertEq(tokenRewards.shares(user1), 50e18, "Shares not removed correctly");
        assertEq(tokenRewards.totalShares(), 50e18, "Total shares not updated after removal");
        assertEq(tokenRewards.totalStakers(), 1, "Total stakers should remain 1");
    }

    function testRemoveAllSharesAndReAdd() public {
        // Add initial shares
        vm.startPrank(address(trackingToken));
        tokenRewards.setShares(user1, 100e18, false);

        // Remove all shares
        tokenRewards.setShares(user1, 100e18, true);

        assertEq(tokenRewards.shares(user1), 0, "Shares should be zero");
        assertEq(tokenRewards.totalShares(), 0, "Total shares should be zero");
        assertEq(tokenRewards.totalStakers(), 0, "Total stakers should be zero");

        // Re-add shares
        tokenRewards.setShares(user1, 50e18, false);
        vm.stopPrank();

        assertEq(tokenRewards.shares(user1), 50e18, "Shares not re-added correctly");
        assertEq(tokenRewards.totalShares(), 50e18, "Total shares not updated after re-adding");
        assertEq(tokenRewards.totalStakers(), 1, "Total stakers not updated after re-adding");
    }

    function testRewardsWithZeroTotalShares() public {
        rewardsWhitelister.setWhitelist(address(rewardsToken), true);

        // Deposit rewards when no shares exist
        uint256 depositAmount = 100e18;
        uint256 balanceBefore = rewardsToken.balanceOf(address(0xdead));

        tokenRewards.depositRewards(address(rewardsToken), depositAmount);

        // Rewards should be burned when total shares are zero
        uint256 balanceAfter = rewardsToken.balanceOf(address(0xdead));
        assertEq(balanceAfter - balanceBefore, depositAmount, "Rewards should be burned when no shares exist");
    }

    // function testPausedAndWhitelistedInteraction() public {
    //     rewardsWhitelister.setWhitelist(address(rewardsToken), true);

    //     // Setup initial state
    //     vm.prank(address(trackingToken));
    //     tokenRewards.setShares(user1, 100e18, false);
    //     tokenRewards.depositRewards(address(rewardsToken), 10e18);

    //     // Pause rewards
    //     rewardsWhitelister.setPaused(true);

    //     // Remove whitelist while paused
    //     rewardsWhitelister.setWhitelist(address(rewardsToken), false);

    //     // Try to deposit while paused and not whitelisted
    //     vm.expectRevert(bytes("V")); // Invalid rewards token
    //     tokenRewards.depositRewards(address(rewardsToken), 10e18);

    //     // Unpause but keep non-whitelisted
    //     rewardsWhitelister.setPaused(false);

    //     // Try to deposit while unpaused but not whitelisted
    //     vm.expectRevert(bytes("V")); // Invalid rewards token
    //     tokenRewards.depositRewards(address(rewardsToken), 10e18);
    // }

    function testMultipleRewardTokens() public {
        // Setup whitelists
        rewardsWhitelister.setWhitelist(address(rewardsToken), true);
        rewardsWhitelister.setWhitelist(address(secondaryRewardToken), true);

        // Add shares
        vm.prank(address(trackingToken));
        tokenRewards.setShares(user1, 100e18, false);

        // Deposit multiple reward tokens
        tokenRewards.depositRewards(address(rewardsToken), 10e18);
        tokenRewards.depositRewards(address(secondaryRewardToken), 5e18);

        // Verify both tokens are tracked
        address[] memory rewardTokens = tokenRewards.getAllRewardsTokens();
        assertEq(rewardTokens.length, 2, "Should track both reward tokens");

        // Check unpaid rewards for both tokens
        uint256 unpaidRewards = tokenRewards.getUnpaid(address(rewardsToken), user1);
        uint256 unpaidSecondary = tokenRewards.getUnpaid(address(secondaryRewardToken), user1);

        assertGt(unpaidRewards, 0, "Should have unpaid rewards");
        assertGt(unpaidSecondary, 0, "Should have unpaid secondary rewards");
    }

    function testRewardDistributionAccuracy() public {
        rewardsWhitelister.setWhitelist(address(rewardsToken), true);

        // Add shares for two users
        vm.startPrank(address(trackingToken));
        tokenRewards.setShares(user1, 60e18, false); // 60%
        tokenRewards.setShares(user2, 40e18, false); // 40%
        vm.stopPrank();

        // Deposit rewards
        uint256 depositAmount = 100e18;
        tokenRewards.depositRewards(address(rewardsToken), depositAmount);

        // Claim rewards for both users
        tokenRewards.claimReward(user1);
        tokenRewards.claimReward(user2);

        // Check distribution accuracy
        uint256 user1Balance = rewardsToken.balanceOf(user1);
        uint256 user2Balance = rewardsToken.balanceOf(user2);

        assertApproxEqRel(user1Balance, 60e18, 1e16, "User1 should receive 60% of rewards");
        assertApproxEqRel(user2Balance, 40e18, 1e16, "User2 should receive 40% of rewards");
    }

    function testInvalidRewardToken() public {
        MockERC20 invalidToken = new MockERC20("Invalid", "INV");
        invalidToken.mint(address(this), 1000e18);
        invalidToken.approve(address(tokenRewards), type(uint256).max);

        vm.expectRevert(bytes("V")); // Invalid rewards token
        tokenRewards.depositRewards(address(invalidToken), 10e18);
    }

    function testZeroAmountDeposit() public {
        rewardsWhitelister.setWhitelist(address(rewardsToken), true);

        vm.expectRevert(bytes("A")); // Amount must be greater than 0
        tokenRewards.depositRewards(address(rewardsToken), 0);
    }

    function testCumulativeRewardsNoRoundUp() public {
        uint256 share = 1000 * 1e18;
        uint256 rewardsPerShare = 5 * PRECISION; // 5 tokens per share

        setRewardsAndCalculate(share, rewardsPerShare, false);
    }

    function testCumulativeRewardsRoundUp() public {
        uint256 share = 1000 * 1e18;
        uint256 rewardsPerShare = 5 * PRECISION + 1; // 5 tokens per share + 1 wei

        setRewardsAndCalculate(share, rewardsPerShare, true);
    }

    function testCumulativeRewardsZeroShare() public {
        uint256 share = 0;
        uint256 rewardsPerShare = 5 * PRECISION;

        setRewardsAndCalculate(share, rewardsPerShare, true);
    }

    function testCumulativeRewardsLargeValues() public {
        uint256 share = 1e24; // 1 million tokens
        uint256 rewardsPerShare = 1e40; // 10,000 tokens per share

        setRewardsAndCalculate(share, rewardsPerShare, false);
    }

    function testCumulativeRewardsSmallValues() public {
        uint256 share = 1; // 1 wei
        uint256 rewardsPerShare = 1; // 1 wei per share

        setRewardsAndCalculate(share, rewardsPerShare, false);
    }

    function testCumulativeRewardsRoundUpEdgeCase() public {
        uint256 share = 1e18;
        uint256 rewardsPerShare = PRECISION - 1; // Just below 1 token per share

        setRewardsAndCalculate(share, rewardsPerShare, true);
    }

    function setRewardsAndCalculate(uint256 share, uint256 rewardsPerShare, bool roundUp) internal {
        address token = address(rewardsToken);
        tokenRewards.setRewardsPerShare(token, rewardsPerShare);

        uint256 result = tokenRewards.exposedCumulativeRewards(token, share, roundUp);
        uint256 expected = calculateExpectedRewards(share, rewardsPerShare, roundUp);

        assertEq(result, expected, "Cumulative rewards calculation incorrect");
    }

    function calculateExpectedRewards(uint256 share, uint256 rewardsPerShare, bool roundUp)
        internal
        pure
        returns (uint256)
    {
        uint256 result = (share * rewardsPerShare) / PRECISION;
        if (roundUp && (share * rewardsPerShare) % PRECISION > 0) {
            result += 1;
        }
        return result;
    }
}

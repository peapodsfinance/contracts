// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/TokenRewards.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Helper contract to expose internal functions for testing
contract TokenRewardsExposed is TokenRewards {
    constructor(
        IProtocolFeeRouter _feeRouter,
        IRewardsWhitelister _rewardsWhitelist,
        IDexAdapter _dexHandler,
        IV3TwapUtilities _v3TwapUtilities,
        address _indexFund,
        address _pairedLpToken,
        address _trackingToken,
        address _rewardsToken
    )
        TokenRewards(
            _indexFund,
            _trackingToken,
            false,
            abi.encode(
                _pairedLpToken,
                _rewardsToken,
                _pairedLpToken,
                address(_feeRouter),
                address(_rewardsWhitelist),
                address(_v3TwapUtilities),
                address(_dexHandler)
            )
        )
    {}

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
}

contract MockProtocolFeeRouter {
    function protocolFees() public pure returns (IProtocolFees) {
        return IProtocolFees(address(0));
    }
}

contract MockRewardsWhitelister {
    function whitelist(address) public pure returns (bool) {
        return true;
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
    TokenRewardsExposed public tokenRewards;
    MockERC20 public pairedToken;
    MockERC20 public rewardsToken;
    MockERC20 public trackingToken;
    MockProtocolFeeRouter public feeRouter;
    MockRewardsWhitelister public rewardsWhitelister;
    MockDexAdapter public dexAdapter;
    MockV3TwapUtilities public v3TwapUtilities;

    uint256 constant PRECISION = 10 ** 27;

    function setUp() public {
        pairedToken = new MockERC20("Paired LP Token", "PLP");
        rewardsToken = new MockERC20("Rewards Token", "RWD");
        trackingToken = new MockERC20("Tracking Token", "TRK");
        feeRouter = new MockProtocolFeeRouter();
        rewardsWhitelister = new MockRewardsWhitelister();
        dexAdapter = new MockDexAdapter();
        v3TwapUtilities = new MockV3TwapUtilities();

        tokenRewards = new TokenRewardsExposed(
            IProtocolFeeRouter(address(feeRouter)),
            IRewardsWhitelister(address(rewardsWhitelister)),
            IDexAdapter(address(dexAdapter)),
            IV3TwapUtilities(address(v3TwapUtilities)),
            address(this),
            address(pairedToken),
            address(trackingToken),
            address(rewardsToken)
        );
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

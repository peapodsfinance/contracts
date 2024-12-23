// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../contracts/IndexUtils.sol";
import "../contracts/WeightedIndex.sol";
import "../contracts/interfaces/IDecentralizedIndex.sol";
import "../contracts/interfaces/IStakingPoolToken.sol";
import {PodHelperTest} from "./helpers/PodHelper.t.sol";

interface IStakingPoolToken_OLD {
    function indexFund() external view returns (address);
}

contract IndexUtilsTest is PodHelperTest {
    address constant peas = 0x02f92800F57BCD74066F5709F1Daa1A4302Df875;
    address constant dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    IndexUtils public utils;

    function setUp() public override {
        super.setUp();
        utils = new IndexUtils(
            IV3TwapUtilities(0x024ff47D552cB222b265D68C7aeB26E586D5229D),
            IDexAdapter(0x7686aa8B32AA9Eb135AC15a549ccd71976c878Bb)
        );
    }

    function test_addLPAndStake() public {
        // Get a pod to test with
        address podToDup = IStakingPoolToken_OLD(0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1).indexFund(); // spPDAI
        address newPod = _dupPodAndSeedLp(podToDup, address(0), 0, 0);
        IDecentralizedIndex indexFund = IDecentralizedIndex(newPod);

        // Setup test amounts
        uint256 podTokensToAdd = 1e18;
        uint256 pairedTokensToAdd = 1e18;
        uint256 slippage = 1000; // 100% slippage for test

        // Deal tokens to this contract
        deal(peas, address(this), podTokensToAdd);
        IERC20(peas).approve(address(indexFund), podTokensToAdd);
        uint256 podBef = indexFund.balanceOf(address(this));
        indexFund.bond(peas, podTokensToAdd, 0);
        uint256 pTknToLp = indexFund.balanceOf(address(this)) - podBef;
        deal(indexFund.PAIRED_LP_TOKEN(), address(this), pairedTokensToAdd);

        // Get initial balances
        uint256 initialPodBalance = IERC20(address(indexFund)).balanceOf(address(this));
        uint256 initialPairedBalance = IERC20(indexFund.PAIRED_LP_TOKEN()).balanceOf(address(this));

        // Approve tokens
        IERC20(address(indexFund)).approve(address(utils), pTknToLp);
        IERC20(indexFund.PAIRED_LP_TOKEN()).approve(address(utils), pairedTokensToAdd);

        // Get initial staked LP balance
        address stakingPool = indexFund.lpStakingPool();
        uint256 initialStakedBalance = IERC20(stakingPool).balanceOf(address(this));

        // Add liquidity and stake
        uint256 lpTokensReceived = utils.addLPAndStake(
            indexFund,
            pTknToLp,
            indexFund.PAIRED_LP_TOKEN(),
            pairedTokensToAdd,
            0, // min paired tokens
            slippage,
            block.timestamp
        );

        // Verify LP tokens were received and staked
        assertGt(lpTokensReceived, 0, "Should receive LP tokens");
        assertGt(
            IERC20(stakingPool).balanceOf(address(this)) - initialStakedBalance, 0, "Staked balance should increase"
        );

        // Verify token balances were reduced
        assertLt(
            IERC20(address(indexFund)).balanceOf(address(this)), initialPodBalance, "Pod token balance should decrease"
        );
        // the extra 1 wei is from the utils CA keeping back 1 wei to save gas for future operations
        assertApproxEqAbs(
            IERC20(indexFund.PAIRED_LP_TOKEN()).balanceOf(address(this)),
            initialPairedBalance - pairedTokensToAdd,
            1, // 1 wei error acceptance due to holding 1 wei behind before LPing
            "Paired token balance should decrease"
        );
        assertEq(IERC20(address(indexFund)).balanceOf(address(utils)), 1, "pTKN balance of utils should be 1 wei");
        assertEq(
            IERC20(indexFund.PAIRED_LP_TOKEN()).balanceOf(address(utils)),
            1,
            "Paired token balance of utils should be 1 wei"
        );
        assertEq(IERC20(stakingPool).balanceOf(address(utils)), 1, "spTKN balance of utils should be 1 wei");
    }

    function test_addLPAndStake_WithEth() public {
        // Get a pod to test with
        address podToDup = IStakingPoolToken_OLD(0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1).indexFund(); // spPDAI
        address newPod = _dupPodAndSeedLp(podToDup, address(0), 0, 0);
        IDecentralizedIndex indexFund = IDecentralizedIndex(newPod);

        // Setup test amounts
        uint256 podTokensToAdd = 1e18;
        uint256 ethToAdd = 1 ether;
        uint256 slippage = 1000; // 100% slippage for test

        // Deal tokens to this contract
        deal(peas, address(this), podTokensToAdd);
        IERC20(peas).approve(address(indexFund), podTokensToAdd);
        uint256 podBef = indexFund.balanceOf(address(this));
        indexFund.bond(peas, podTokensToAdd, 0);
        uint256 pTknToLp = indexFund.balanceOf(address(this)) - podBef;
        vm.deal(address(this), ethToAdd);

        // Get initial balances
        uint256 initialPodBalance = IERC20(address(indexFund)).balanceOf(address(this));
        uint256 initialEthBalance = address(this).balance;

        // Approve tokens
        IERC20(address(indexFund)).approve(address(utils), pTknToLp);

        // Get initial staked LP balance
        address stakingPool = indexFund.lpStakingPool();
        uint256 initialStakedBalance = IERC20(stakingPool).balanceOf(address(this));

        // Add liquidity and stake with ETH
        uint256 lpTokensReceived = utils.addLPAndStake{value: ethToAdd}(
            indexFund,
            pTknToLp,
            address(0), // Use ETH
            ethToAdd,
            0, // min paired tokens
            slippage,
            block.timestamp
        );

        // Verify LP tokens were received and staked
        assertGt(lpTokensReceived, 0, "Should receive LP tokens");
        assertGt(
            IERC20(stakingPool).balanceOf(address(this)) - initialStakedBalance, 0, "Staked balance should increase"
        );

        // Verify token balances were reduced
        assertLt(
            IERC20(address(indexFund)).balanceOf(address(this)), initialPodBalance, "Pod token balance should decrease"
        );
        assertLt(address(this).balance, initialEthBalance, "ETH balance should decrease");
    }

    function test_bond_SingleAsset() public {
        // Get a pod with single asset
        address podToDup = IStakingPoolToken_OLD(0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1).indexFund(); // spPDAI
        address newPod = _dupPodAndSeedLp(podToDup, address(0), 0, 0);
        IDecentralizedIndex indexFund = IDecentralizedIndex(newPod);

        // Get the underlying asset
        IDecentralizedIndex.IndexAssetInfo[] memory assets = indexFund.getAllAssets();
        address underlyingToken = assets[0].token;
        uint256 bondAmount = 1e18;

        // Deal tokens and approve
        deal(underlyingToken, address(this), bondAmount);
        IERC20(underlyingToken).approve(address(utils), bondAmount);

        // Get initial balances
        uint256 initialTokenBalance = IERC20(underlyingToken).balanceOf(address(this));
        uint256 initialPodBalance = IERC20(address(indexFund)).balanceOf(address(this));

        // Bond through utils
        utils.bond(indexFund, underlyingToken, bondAmount, 0);

        // Verify token transfer
        assertApproxEqAbs(
            IERC20(underlyingToken).balanceOf(address(this)),
            initialTokenBalance - bondAmount,
            1, // 1 wei forgiveness for rounding down
            "Token balance should decrease by bond amount"
        );

        // Verify pod tokens received
        assertGt(IERC20(address(indexFund)).balanceOf(address(this)), initialPodBalance, "Should receive pod tokens");
    }

    function test_bond_MultipleAssets() public {
        // Create a pod with multiple assets
        address[] memory tokens = new address[](2);
        tokens[0] = peas;
        tokens[1] = dai;
        uint256[] memory weights = new uint256[](2);
        weights[0] = 50;
        weights[1] = (weights[0] * 3) / 2;

        IDecentralizedIndex.Config memory config;
        IDecentralizedIndex.Fees memory fees;

        address newPod = _createPod(
            "Test Multi",
            "tMULTI",
            config,
            fees,
            tokens,
            weights,
            address(0),
            false,
            _getImmutables(dai, 0x7686aa8B32AA9Eb135AC15a549ccd71976c878Bb)
        );
        IDecentralizedIndex indexFund = IDecentralizedIndex(newPod);

        // Setup bond amounts
        uint256 bondAmount = 1e18;

        // Deal tokens and approve
        deal(peas, address(this), bondAmount);
        IERC20(peas).approve(address(utils), bondAmount);
        deal(dai, address(this), (bondAmount * 3) / 2);
        IERC20(dai).approve(address(utils), (bondAmount * 3) / 2);

        // Get initial balances
        uint256 initialPeasBalance = IERC20(peas).balanceOf(address(this));
        uint256 initialDaiBalance = IERC20(dai).balanceOf(address(this));
        uint256 initialPodBalance = IERC20(address(indexFund)).balanceOf(address(this));

        // Bond through utils
        utils.bond(indexFund, peas, bondAmount, 0);

        // Verify token transfers
        assertApproxEqAbs(
            IERC20(peas).balanceOf(address(this)),
            initialPeasBalance - bondAmount,
            1, // 1 wei forgiveness for rounding down
            "PEAS balance should decrease by bond amount"
        );
        assertApproxEqAbs(
            IERC20(dai).balanceOf(address(this)),
            initialDaiBalance - ((bondAmount * 3) / 2),
            1, // 1 wei forgiveness for rounding down
            "DAI balance should decrease by bond amount"
        );

        // Verify pod tokens received
        assertGt(IERC20(address(indexFund)).balanceOf(address(this)), initialPodBalance, "Should receive pod tokens");
    }

    function test_bond_RefundsExcess() public {
        // Get a pod with single asset
        address podToDup = IStakingPoolToken_OLD(0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1).indexFund(); // spPDAI
        address newPod = _dupPodAndSeedLp(podToDup, address(0), 0, 0);
        IDecentralizedIndex indexFund = IDecentralizedIndex(newPod);

        // Get the underlying asset
        IDecentralizedIndex.IndexAssetInfo[] memory assets = indexFund.getAllAssets();
        address underlyingToken = assets[0].token;
        uint256 bondAmount = 1e18;
        uint256 excessAmount = 0.5e18;

        // Deal extra tokens and approve
        deal(underlyingToken, address(this), bondAmount + excessAmount);
        IERC20(underlyingToken).approve(address(utils), bondAmount + excessAmount);

        // Get initial balance
        uint256 initialTokenBalance = IERC20(underlyingToken).balanceOf(address(this));

        // Bond through utils
        utils.bond(indexFund, underlyingToken, bondAmount, 0);

        // Verify excess was refunded
        assertApproxEqAbs(
            IERC20(underlyingToken).balanceOf(address(this)),
            initialTokenBalance - bondAmount,
            1, // 1 wei forgiveness for rounding down
            "Should only use bondAmount and refund excess"
        );
    }

    function test_preventReentrancyFlashMint() public {
        // Get a pod to test with
        address podToDup = IStakingPoolToken_OLD(0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1).indexFund(); // spPDAI
        address newPod = _dupPodAndSeedLp(podToDup, address(0), 0, 0);
        IDecentralizedIndex indexFund = IDecentralizedIndex(newPod);

        // Setup test amounts
        uint256 podTokensToAdd = 1e18;
        uint256 pairedTokensToAdd = 1e18;

        // Deal tokens to this contract
        deal(peas, address(this), podTokensToAdd + 1000);
        // attacker balance before
        // uint256 peasBefore = IERC20(peas).balanceOf(address(this));
        IERC20(peas).approve(address(indexFund), podTokensToAdd + 1000);
        uint256 podBef = indexFund.balanceOf(address(this));
        indexFund.bond(peas, podTokensToAdd + 1000, 0);
        deal(indexFund.PAIRED_LP_TOKEN(), address(this), pairedTokensToAdd);

        // uint256 initialPairedBalance = IERC20(indexFund.PAIRED_LP_TOKEN())
        //     .balanceOf(address(this));

        // Approve tokens
        IERC20(indexFund.PAIRED_LP_TOKEN()).approve(address(indexFund), pairedTokensToAdd);

        uint256 lpAmount = indexFund.addLiquidityV2(
            indexFund.balanceOf(address(this)) - podBef - 10,
            pairedTokensToAdd,
            1000, // 100% slippage for test
            block.timestamp
        );

        // Get initial staked LP balance
        address stakingPool = indexFund.lpStakingPool();

        // Deal tokens to the indexFund to simulate accumulated reward fees
        deal(address(indexFund), address(indexFund), 100e18);

        bytes memory data = abi.encode(indexFund, stakingPool, lpAmount);
        vm.expectRevert();
        indexFund.flashMint(address(this), 0, data);
    }

    // NOTE: required for test_preventReentrancyFlashMint
    function callback(bytes calldata data) external {
        (, address stakingPool, uint256 lpAmount) = abi.decode(data, (address, address, uint256));
        address _podV2Pool = IStakingPoolToken(stakingPool).stakingToken();
        IERC20(_podV2Pool).approve(stakingPool, lpAmount);
        IStakingPoolToken(stakingPool).stake(address(this), lpAmount);
    }

    receive() external payable {}
}

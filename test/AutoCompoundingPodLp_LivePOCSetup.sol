// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {LivePOC} from "./helpers/LivePOC.t.sol";
import {ILeverageManager} from "../contracts/interfaces/ILeverageManager.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract AutoCompoundingPodLp_LivePOCSetup is LivePOC {
    function testAutoCompoundSelfLendingRewardSwapConvertedToFtkn() public {
        // Simulate WETH rewards
        deal(weth, address(selfLending_aspTkn), 1e18);
        uint256 daiBalanceBefore = DAI.balanceOf(address(selfLending_aspTkn));

        uint256 totalAssetsBefore = selfLending_aspTkn.totalAssets();
        uint256 processedLp = selfLending_aspTkn.processAllRewardsTokensToPodLp(0, block.timestamp);
        assertGt(processedLp, 0, "LP was not processed since none was added");

        uint256 totalAssetsAfter = selfLending_aspTkn.totalAssets();
        uint256 daiBalanceAfter = DAI.balanceOf(address(selfLending_aspTkn));

        assertEq(daiBalanceAfter, daiBalanceBefore, "DAI was processed and none leftover");
        assertLt(totalAssetsBefore, totalAssetsAfter, "New assets were added");
    }

    function testAutoCompoundOneWayLPSwapLeftovers() public {
        deal(address(peas), address(aspTkn), 100e18);

        // 2 tokens: pTKN, DAI
        uint256 daiBalanceBefore = DAI.balanceOf(address(aspTkn));
        uint256 podBalanceBefore = pod.balanceOf(address(aspTkn));

        DAI.approve(address(aspTkn), type(uint256).max);
        pod.approve(address(aspTkn), type(uint256).max);
        uint256 processedLp = aspTkn.processAllRewardsTokensToPodLp(0, block.timestamp);
        assertGt(processedLp, 0, "LP was not processed since none was added");
        aspTkn.withdrawProtocolFees();

        uint256 daiBalanceAfter = DAI.balanceOf(address(aspTkn));
        uint256 podBalanceAfter = pod.balanceOf(address(aspTkn));

        assertApproxEqAbs(
            daiBalanceBefore,
            daiBalanceAfter,
            1e17, // 10 wei error
            "More DAI remaining than expected"
        );
        assertApproxEqAbs(
            podBalanceBefore,
            podBalanceAfter,
            1e17, // 10 wei error
            "More pTKN remaining than expected"
        );
    }
}

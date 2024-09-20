// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {BeforeAfter} from "./BeforeAfter.sol";

contract Properties is BeforeAfter {
    
    function invariant_POD_1() internal { 
        fl.t(false, "POD-1: LeverageManager::_acquireBorrowTokenForRepayment should never Uniswap revert");
    }

    function invariant_POD_2(uint256 shares) internal {
        // LendingAssetVault::deposit share balance of receiver should increase
        // LendingAssetVault::mint share balance of receiver should increase
        fl.eq(
            _afterLav.receiverShareBalance,
            _beforeLav.receiverShareBalance + shares,
            "POD-2: Share balance of receiver should increase"
        );
    }

    function invariant_POD_3(uint256 shares) internal {
        // LendingAssetVault::withdraw share balance of user should decrease
        // LendingAssetVault::redeem share balance of user should decrease
        fl.eq(
            _afterLav.userShareBalance,
            _beforeLav.userShareBalance - shares,
            "POD-2: Share balance of user should decrease"
        );
    }
}
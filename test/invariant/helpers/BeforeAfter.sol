// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {FuzzSetup} from "../FuzzSetup.sol";

contract BeforeAfter is FuzzSetup {

    struct LavVars {
        uint256 userShareBalance;
        uint256 receiverShareBalance;
    }

    LavVars internal _beforeLav;
    LavVars internal _afterLav;

    function __beforeLav(address user, address receiver) internal {
        _beforeLav.userShareBalance = _lendingAssetVault.balanceOf(user);
        _beforeLav.receiverShareBalance = _lendingAssetVault.balanceOf(receiver);
    }

    function __afterLav(address user, address receiver) internal {
        _afterLav.userShareBalance = _lendingAssetVault.balanceOf(user);
        _afterLav.receiverShareBalance = _lendingAssetVault.balanceOf(receiver);
    }
}
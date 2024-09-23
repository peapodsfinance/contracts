// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {BeforeAfter} from "./BeforeAfter.sol";

import {FraxlendPair} from "../modules/fraxlend/FraxlendPair.sol";

contract Properties is BeforeAfter {
    
    function invariant_POD_1() internal { 
        fl.t(false, "POD-1: LeverageManager::_acquireBorrowTokenForRepayment should never Uniswap revert");
    }

    function invariant_POD_2(uint256 shares) internal {
        // LendingAssetVault::deposit share balance of receiver should increase
        // LendingAssetVault::mint share balance of receiver should increase
        fl.gte(
            _afterLav.receiverShareBalance,
            _beforeLav.receiverShareBalance, // + shares,
            //10000,
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

    function invariant_POD_4(FraxlendPair fraxPair) internal {
        // LendingAssetVault::vaultUtilization[_vault] 
        // vaultUtilization[_vault] == FraxLend.convertToAssets(LAV shares) post-update
        assertApproxEq(
            _afterLM.vaultUtilization,
            fraxPair.convertToAssets(fraxPair.balanceOf(address(_lendingAssetVault))),
            10000,
            "POD-4: vaultUtilization[_vault] == FraxLend.convertToAssets(LAV shares) post-update"
        );
    }

    function invariant_POD_5() public {
        // LendingAssetVault::totalAssetsUtilized  totalAssetsUtilized == sum(all vault utilizations)
        uint256 utilizationSum;
        for (uint256 i; i < _fraxPairs.length; i++) {
            utilizationSum += _lendingAssetVault.vaultUtilization(address(_fraxPairs[i]));
        }

        fl.eq(
            utilizationSum,
            _lendingAssetVault.totalAssetsUtilized(),
            "POD-5: LendingAssetVault::totalAssetsUtilized  totalAssetsUtilized == sum(all vault utilizations)"
        );
    }

    function invariant_POD_6() internal {
        // LendingAssetVault::whitelistDeposit totalAvailableAssets() should increase
        fl.gte(
            _afterLM.totalAvailableAssets,
            _beforeLM.totalAvailableAssets,
            "POD-6: LendingAssetVault::whitelistDeposit totalAvailableAssets() should increase"
        );
    }

    function invariant_POD_7(uint256 assets) internal {
        // LendingAssetVault::whitelistDeposit vault utilization should decrease accurately
        fl.eq(
            _afterLM.vaultUtilization,
            _beforeLM.vaultUtilization - assets,
            "POD-7: LendingAssetVault::whitelistDeposit vault utilization should decrease accurately"
        );
    }

    function invariant_POD_8(uint256 assets) internal {
        // LendingAssetVault::whitelistDeposit total utilization should decrease accurately
        fl.eq(
            _afterLM.totalAssetsUtilized,
            _beforeLM.totalAssetsUtilized - assets,
            "POD-8: LendingAssetVault::whitelistDeposit total utilization should decrease accurately"
        );
    }

    function invariant_POD_9() internal {
        // LendingAssetVault::whitelistWithdraw totalAvailableAssets() should decrease
        fl.lte(
            _afterLM.totalAvailableAssets,
            _beforeLM.totalAvailableAssets,
            "POD-9: LendingAssetVault::whitelistWithdrawtotalAvailableAssets() should decrease"
        );
    }

    function invariant_POD_10(uint256 assets) internal {
        // LendingAssetVault::whitelistWithdraw vault utilization should increase accurately
        fl.eq(
            _afterLM.vaultUtilization,
            _beforeLM.vaultUtilization + assets,
            "POD-7: LendingAssetVault::whitelistWithdraw vault utilization should increase accurately"
        );
    }

    function invariant_POD_11(uint256 assets) internal {
        // LendingAssetVault::whitelistWithdraw total utilization should increase accurately
        fl.eq(
            _afterLM.totalAssetsUtilized,
            _beforeLM.totalAssetsUtilized + assets,
            "POD-7: LendingAssetVault::whitelistWithdraw total utilization should increase accurately"
        );
    }

}
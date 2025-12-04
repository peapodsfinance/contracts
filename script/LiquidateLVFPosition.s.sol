// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20, IFraxlendPair} from "../contracts/interfaces/IFraxlendPair.sol";
import {VaultAccount, VaultAccountingLibrary} from "../contracts/libraries/VaultAccount.sol";

contract LiquidateLVFPosition is Script {
    using VaultAccountingLibrary for VaultAccount;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address _lendingPair = vm.envAddress("PAIR");
        address _borrower = vm.envAddress("BORROWER");

        (,,,,, VaultAccount memory _totalBorrow) = IFraxlendPair(_lendingPair).previewAddInterest();
        uint256 _debtTotalShares = IFraxlendPair(_lendingPair).userBorrowShares(_borrower);
        uint256 _debtFromCollateral = IFraxlendPair(_lendingPair).exchangeRateInfo().highExchangeRate == 0
            ? 0
            : (10 ** 18 * IFraxlendPair(_lendingPair).userCollateralBalance(_borrower))
                / IFraxlendPair(_lendingPair).exchangeRateInfo().highExchangeRate;
        uint256 _debtSharesFromCollateral =
            (_debtFromCollateral * _debtTotalShares) / _totalBorrow.toAmount(_debtTotalShares, true);
        uint128 _sharesToLiquidate = uint128(_debtSharesFromCollateral);
        _sharesToLiquidate =
            uint128(_sharesToLiquidate > _debtTotalShares ? _debtTotalShares : (_sharesToLiquidate * 1001) / 1000);

        // Log before state
        console2.log(
            "Before - Borrow shares:", Strings.toString(IFraxlendPair(_lendingPair).userBorrowShares(_borrower))
        );
        console2.log(
            "Before - Collateral:", Strings.toString(IFraxlendPair(_lendingPair).userCollateralBalance(_borrower))
        );
        console2.log("Before - Deployer ETH balance:", Strings.toString(vm.addr(deployerPrivateKey).balance / 10 ** 14));
        console2.log(
            "Before - Deployer asset balance:",
            Strings.toString(IERC20(IFraxlendPair(_lendingPair).asset()).balanceOf(vm.addr(deployerPrivateKey)))
        );

        if (IERC20(IFraxlendPair(_lendingPair).asset()).allowance(vm.addr(deployerPrivateKey), _lendingPair) < 1e18) {
            IERC20(IFraxlendPair(_lendingPair).asset()).approve(_lendingPair, type(uint256).max);
        }
        IFraxlendPair(_lendingPair).liquidate(_sharesToLiquidate, block.timestamp + 600, _borrower);
        // IERC4626(IFraxlendPair(_lendingPair).collateralContract())
        //     .redeem(
        //         IERC20(IFraxlendPair(_lendingPair).collateralContract()).balanceOf(vm.addr(deployerPrivateKey)),
        //         vm.addr(deployerPrivateKey),
        //         vm.addr(deployerPrivateKey)
        //     );

        // Log after state
        console2.log(
            "After - Borrow shares:", Strings.toString(IFraxlendPair(_lendingPair).userBorrowShares(_borrower))
        );
        console2.log(
            "After - Collateral:", Strings.toString(IFraxlendPair(_lendingPair).userCollateralBalance(_borrower))
        );
        console2.log("After - Deployer ETH balance:", Strings.toString(vm.addr(deployerPrivateKey).balance / 10 ** 14));
        console2.log(
            "After - Deployer asset balance:",
            Strings.toString(IERC20(IFraxlendPair(_lendingPair).asset()).balanceOf(vm.addr(deployerPrivateKey)))
        );
    }
}

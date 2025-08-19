// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {FraxlendLiquidator} from "../contracts/liquidator/FraxlendLiquidator.sol";
import {IFraxlendPair} from "../contracts/interfaces/IFraxlendPair.sol";
import {IStakingPoolToken} from "../contracts/interfaces/IStakingPoolToken.sol";
import {VaultAccount, VaultAccountingLibrary} from "../contracts/libraries/VaultAccount.sol";

contract DeployAndExecuteFraxlendLiquidator is Script {
    using VaultAccountingLibrary for VaultAccount;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // address leverageManagerAddress = vm.envAddress("LEVERAGE_MANAGER");
        // uint256 positionId = vm.envUint("POSITION_ID");
        uint128 _sharesToLiquidate = uint128(vm.envUint("SHARES"));

        // podETH (0x82788C99bd80Ad2D7BBa1fB12b0EaC97ccF2E91f) pair: 0xca1154bBD62C21868a358f9f782b90D69Af600B0
        // pLONGsUSDe (0x5c3ab44bbdd5d244eb7c920acc5404080da947d5) pair: 0x2e4cbec7f29cb74a84511119757ff3ce1ef38271
        address _lendingPair = vm.envAddress("PAIR");

        // podETH borrower: 0x80BF7Db69556D9521c03461978B8fC731DBBD4e4
        // pLONGsUSDe borrower: 0x7212DE58f97aD6C28623752479Acaeb6b15aD006
        address _borrower = vm.envAddress("BORROWER");

        (,,,,, VaultAccount memory _totalBorrow) = IFraxlendPair(_lendingPair).previewAddInterest();
        uint256 _amountAssets = _totalBorrow.toAmount(_sharesToLiquidate, true);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy FraxlendLiquidator
        // FraxlendLiquidator liquidator = new FraxlendLiquidator(leverageManagerAddress);
        FraxlendLiquidator liquidator = FraxlendLiquidator(0xB6C55cf07677fA1368D6C8A00e7B0091B9a4C9BB);

        // console2.log("FraxlendLiquidator deployed to:", address(liquidator));
        // console2.log("Position ID to liquidate:", positionId);
        console2.log("Shares to liquidate:", _sharesToLiquidate);

        console2.log(
            "current collateral info",
            IFraxlendPair(_lendingPair).userCollateralBalance(_borrower),
            IFraxlendPair(_lendingPair).collateralContract()
        );
        uint256 _positionTotalShares = IFraxlendPair(_lendingPair).userBorrowShares(_borrower);
        console2.log(
            "total position debt info",
            _positionTotalShares,
            _totalBorrow.toAmount(_positionTotalShares, true),
            IFraxlendPair(_lendingPair).asset()
        );
        console2.log("liquidation debt info", _sharesToLiquidate, _amountAssets, IFraxlendPair(_lendingPair).asset());

        // address _aspTkn = IFraxlendPair(_lendingPair).collateralContract();
        // address _spTkn = IERC4626(IFraxlendPair(_lendingPair).collateralContract()).asset();
        address _pod =
            IStakingPoolToken(IERC4626(IFraxlendPair(_lendingPair).collateralContract()).asset()).INDEX_FUND();

        // Execute liquidation
        if (
            IERC20(IFraxlendPair(_lendingPair).asset()).allowance(vm.addr(deployerPrivateKey), address(liquidator)) == 0
        ) {
            IERC20(IFraxlendPair(_lendingPair).asset()).approve(address(liquidator), type(uint256).max);
        }

        console2.log(
            "pTKN before:", IERC20(_pod).balanceOf(address(vm.addr(deployerPrivateKey))), IERC20Metadata(_pod).symbol()
        );
        console2.log(
            "fTKN before:",
            IERC20(_lendingPair).balanceOf(address(vm.addr(deployerPrivateKey))),
            IERC20Metadata(_lendingPair).symbol()
        );
        console2.log(
            "CBR before:", (10 ** 18 * IERC4626(_lendingPair).totalAssets()) / IERC20(_lendingPair).totalSupply()
        );

        liquidator.liquidateDirectly(_sharesToLiquidate, _lendingPair, _borrower);

        console2.log(
            "CBR after-:", (10 ** 18 * IERC4626(_lendingPair).totalAssets()) / IERC20(_lendingPair).totalSupply()
        );
        console2.log(
            "pTKN after:", IERC20(_pod).balanceOf(address(vm.addr(deployerPrivateKey))), IERC20Metadata(_pod).symbol()
        );
        console2.log(
            "fTKN after:",
            IERC20(_lendingPair).balanceOf(address(vm.addr(deployerPrivateKey))),
            IERC20Metadata(_lendingPair).symbol()
        );

        vm.stopBroadcast();
    }
}

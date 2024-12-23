// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../contracts/lvf/LeverageManager.sol";

contract RemoveLeverageLeverageManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address lvf = vm.envAddress("LVF");
        uint256 borrowAmt = vm.envUint("BORROW_AMOUNT");
        uint256 collateralAmt = vm.envUint("COLLATERAL");
        uint256 positionId = vm.envUint("POS_ID");

        (, address lendingPair,,,) = LeverageManager(payable(lvf)).positionProps(positionId);
        IERC20(IERC4626(lendingPair).asset()).approve(lvf, 1000e18);
        LeverageManager(payable(lvf)).removeLeverage(positionId, borrowAmt, collateralAmt, 0, 0, 0, 1000e18);

        vm.stopBroadcast();

        console.log("Successfully removed leverage!");
    }
}

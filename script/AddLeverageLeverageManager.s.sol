// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../contracts/lvf/LeverageManager.sol";

contract AddLeverageLeverageManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address lvf = vm.envAddress("LVF");
        address pod = vm.envAddress("POD");
        uint256 ptknAmt = vm.envUint("AMOUNT");
        uint256 positionId = vm.envUint("POS_ID");

        IERC20(pod).approve(lvf, ptknAmt);
        LeverageManager(payable(lvf)).addLeverage(
            positionId, pod, ptknAmt, ptknAmt, 0, false, abi.encode(0, 1000, block.timestamp + 120)
        );

        vm.stopBroadcast();

        console.log("Successfully added leverage!");
    }
}

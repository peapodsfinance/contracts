// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../contracts/lvf/LeverageManager.sol";
import "../contracts/lvf/LeveragePositions.sol";
import {FraxlendPairCore} from "../test/invariant/modules/fraxlend/FraxlendPairCore.sol";

contract GetLeveragePositionInfoScript is Script {
    function run() external view {
        address lvf = vm.envAddress("LVF");
        uint256 positionId = vm.envUint("POS_ID");

        (address pod, address lendingPair, address custodian, bool isSelfLending, bool hasSelfLendingPairPod) =
            LeverageManager(payable(lvf)).positionProps(positionId);
        uint256 _custodianCollBal = FraxlendPairCore(lendingPair).userCollateralBalance(custodian);
        uint256 _custodianBorrowShares = FraxlendPairCore(lendingPair).userBorrowShares(custodian);

        console.log("Owner:", LeverageManager(payable(lvf)).positionNFT().ownerOf(positionId));
        console.log("Pod:", pod);
        console.log("Lending Pair:", lendingPair);
        console.log("Custodian:", custodian);
        console.log("Custodian collateral balance in lending pair:", _custodianCollBal);
        console.log("Custodian borrow shares in lending pair:", _custodianBorrowShares);
        console.log("Is self lending:", isSelfLending);
        console.log("Has self lending pair pod:", hasSelfLendingPairPod);
    }
}

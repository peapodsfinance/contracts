// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IIndexManager, IndexManager} from "../contracts/IndexManager.sol";
import {LeverageManager} from "../contracts/lvf/LeverageManager.sol";
import {FraxlendPair} from "../test/invariant/modules/fraxlend/FraxlendPair.sol";

contract WithdrawFees is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address treasury = 0x88eaFE23769a4FC2bBF52E77767C3693e6acFbD5;
        address indexManager = vm.envAddress("INDEX_MANAGER");
        address leverageManager = vm.envAddress("LVF");

        IIndexManager.IIndexAndStatus[] memory pods = IndexManager(indexManager).allIndexes();
        for (uint256 _i; _i < pods.length; _i++) {
            address _pod = pods[_i].index;
            address lendingPair = LeverageManager(payable(leverageManager)).lendingPairs(_pod);
            if (lendingPair == address(0)) {
                continue;
            }

            if (vm.addr(vm.envUint("PRIVATE_KEY")) != FraxlendPair(lendingPair).owner()) {
                continue;
            }

            uint256 _shares = IERC20(lendingPair).balanceOf(lendingPair);
            if (_shares == 0) {
                continue;
            }

            address asset = FraxlendPair(lendingPair).asset();
            uint8 decimals = IERC20Metadata(asset).decimals();
            uint256 _assetsForShares = FraxlendPair(lendingPair).convertToAssets(_shares);
            if (_assetsForShares > IERC20(asset).balanceOf(lendingPair)) {
                continue;
            }

            (uint256 i, uint256 f) = _getFloat(IERC20(asset).balanceOf(treasury), decimals);
            console.log("processing lending pair: %s", lendingPair);
            console.log("Treasury balance before: %s.%s %s", i, f, IERC20Metadata(asset).symbol());

            FraxlendPair(lendingPair).withdrawFees(uint128(_shares), treasury);

            (i, f) = _getFloat(IERC20(asset).balanceOf(treasury), decimals);
            console.log("Treasury balance after: %s.%s %s", i, f, IERC20Metadata(asset).symbol());
        }

        vm.stopBroadcast();

        console.log("Success!");
    }

    function _getFloat(uint256 num, uint8 decimals) internal pure returns (uint256 integerPart, uint256 decimalPart) {
        uint256 factor = 10 ** decimals;
        integerPart = num / factor;
        decimalPart = num % factor;
    }
}

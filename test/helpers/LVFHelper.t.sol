// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {LeverageManager} from "../../contracts/lvf/LeverageManager.sol";
import {LeveragePositions} from "../../contracts/lvf/LeveragePositions.sol";

contract LVFHelper {
    function _deployLeverageManager(
        string memory _positionName,
        string memory _positionSymbol,
        address _idxUtils,
        address _feeReceiver
    ) internal returns (address payable lvf) {
        address lvfImpl = address(new LeverageManager());
        address lvfBeacon = address(new UpgradeableBeacon(lvfImpl, msg.sender));
        bytes memory lvfInitData =
            abi.encodeWithSelector(LeverageManager.initialize.selector, address(0), _idxUtils, _feeReceiver);
        lvf = payable(address(new BeaconProxy(address(lvfBeacon), lvfInitData)));
        LeveragePositions lvfPositions = new LeveragePositions(_positionName, _positionSymbol, lvf);
        LeverageManager(lvf).setPositionNFT(lvfPositions);
    }
}

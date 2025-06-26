// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "../contracts/lvf/LeverageManager.sol";
import "../contracts/lvf/LeveragePositions.sol";

contract DeployLeverageManager is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        uint16 openFee = uint16(vm.envUint("OPEN_FEE"));
        uint16 closeFee = uint16(vm.envUint("CLOSE_FEE"));

        vm.startBroadcast(deployerPrivateKey);

        // Deploy implementation
        LeverageManager lvfImpl = new LeverageManager();
        console.log("LeverageManager Implementation deployed at:", address(lvfImpl));

        // Deploy beacon
        UpgradeableBeacon lvfBeacon = new UpgradeableBeacon(address(lvfImpl), vm.addr(deployerPrivateKey));
        console.log("LeverageManager Beacon deployed at:", address(lvfBeacon));

        bytes memory lvfInitData = abi.encodeWithSelector(
            LeverageManager.initialize.selector, address(0), vm.envAddress("INDEX_UTILS"), vm.envAddress("FEE_RECEIVER")
        );
        address leverageManager = address(new BeaconProxy(address(lvfBeacon), lvfInitData));
        console.log("LeverageManager instance/proxy deployed at:", address(leverageManager));

        LeveragePositions leveragePositions =
            new LeveragePositions(vm.envString("POSITION_NAME"), vm.envString("POSITION_SYMBOL"), leverageManager);

        LeverageManager(payable(leverageManager)).setPositionNFT(leveragePositions);
        LeverageManager(payable(leverageManager)).setOpenFeePerc(openFee);
        LeverageManager(payable(leverageManager)).setCloseFeePerc(closeFee);

        vm.stopBroadcast();
    }
}

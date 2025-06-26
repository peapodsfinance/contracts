// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../contracts/lvf/LeverageFactory.sol";

contract DeployVerificationLVFPod is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        IDecentralizedIndex.Config memory _c;
        address[] memory _t = new address[](1);
        _t[0] = 0x02f92800F57BCD74066F5709F1Daa1A4302Df875;
        uint256[] memory _w = new uint256[](1);
        _w[0] = 1e18;
        (address _pod,,,) = LeverageFactory(vm.envAddress("LEV_FACTORY")).createPodAndAddLvfSupport(
            vm.envAddress("BORROW"),
            abi.encode(
                "Verification LVF",
                "pVERLVF",
                abi.encode(_c, _getFees(), _t, _w, address(0), false),
                _getImmutables(
                    vm.envAddress("DAI"),
                    vm.envAddress("FEE_ROUTER"),
                    vm.envAddress("REWARDS"),
                    vm.envAddress("TWAP_UTILS"),
                    vm.envAddress("ADAPTER")
                )
            ),
            abi.encode(
                0xee7013B65f3b2c789Da629CC58C793A995D4C611, // sepolia
                0xEA1E16d9099C7D56aeC026432ED7024e21b9a41E, // sepolia
                0xCf4A27939a9c3fddEf6D9752F47448Ecc369be7C, // sepolia
                vm.envAddress("BORROW"),
                false,
                false,
                address(0),
                0x1d8F62930d8159be59280060eEEBf226F0a66a6e // sepolia
            ),
            abi.encode(
                address(0),
                address(0),
                address(0),
                address(0),
                address(0),
                0xe965525c2e4f9Da6B9f6F80E0900c538f439Fe70 // sepolia
            ),
            abi.encode(
                uint32(5000), // uint32 _maxOracleDeviation
                0xd0DE14604E7B64FF22EaA5Aafc2C520C04A9bE59, // sepolia // address _rateContract
                uint64(90000), // uint64 _fullUtilizationRate
                60000, // uint256 _maxLTV
                10000, // uint256 _cleanLiquidationFee
                10000, // uint256 _dirtyLiquidationFee
                1000 // uint256 _protocolLiquidationFee
            ),
            false
        );

        vm.stopBroadcast();

        console.log("Pod deployed to:", _pod);
    }

    function _getFees() internal pure returns (IDecentralizedIndex.Fees memory) {
        return IDecentralizedIndex.Fees({
            burn: uint16(2000),
            bond: uint16(100),
            debond: uint16(100),
            buy: uint16(50),
            sell: uint16(50),
            partner: uint16(0)
        });
    }

    function _getImmutables(
        address dai,
        address feeRouter,
        address rewardsWhitelist,
        address twapUtils,
        address dexAdapter
    ) internal pure returns (bytes memory) {
        return abi.encode(
            dai, 0x02f92800F57BCD74066F5709F1Daa1A4302Df875, dai, feeRouter, rewardsWhitelist, twapUtils, dexAdapter
        );
    }
}

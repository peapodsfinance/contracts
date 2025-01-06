// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MockFraxlendPair} from "./MockFraxlendPair.sol";

contract MockFraxlendPairDeployer {
    uint256 public defaultDepositAmt;

    function deploy(bytes memory _configData) external returns (address _pairAddress) {
        (address _borrowTkn, address _collateralTkn,,,,,,,) =
            abi.decode(_configData, (address, address, address, uint32, address, uint64, uint256, uint256, uint256));
        _pairAddress = address(new MockFraxlendPair(_borrowTkn, _collateralTkn));
    }
}

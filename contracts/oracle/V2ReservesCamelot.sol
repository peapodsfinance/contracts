// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../interfaces/ICamelotPair.sol";
import "../interfaces/IV2Reserves.sol";

contract V2ReservesCamelot is IV2Reserves {
    function getReserves(address _pair) external view virtual override returns (uint112 _reserve0, uint112 _reserve1) {
        (_reserve0, _reserve1,,) = ICamelotPair(_pair).getReserves();
    }
}

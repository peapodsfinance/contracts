// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IRateCalculatorV2 {
    function getNewRate(uint256 _deltaTime, uint256 _utilization, uint64 _maxInterest)
        external
        view
        returns (uint64 _newRatePerSec, uint64 _newMaxInterest);
}

contract FixedInterestRateModel is IRateCalculatorV2 {
    uint64 immutable RATE;

    constructor(uint64 _rate) {
        RATE = _rate;
    }

    function getNewRate(uint256, uint256, uint64) external view override returns (uint64, uint64) {
        return (RATE, RATE);
    }
}

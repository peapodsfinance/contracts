// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICurvePool {
    function coins(uint256 _idx) external returns (address);

    function exchange(int128 i, int128 j, uint256 dx, uint256 minDy, address receiver) external returns (uint256);
}

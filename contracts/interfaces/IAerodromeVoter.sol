// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAerodromeVoter {
    function gauges(address pool) external view returns (address);

    function claimRewards(address[] memory _gauges) external;
}

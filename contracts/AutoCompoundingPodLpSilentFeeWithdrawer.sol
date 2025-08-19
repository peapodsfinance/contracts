// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IAutoCompoundingPodLp {
    function withdrawProtocolFees() external;
}

contract AutoCompoundingPodLpSilentFeeWithdrawer {
    function withdrawProtocolFees(address _aspTkn) external returns (bool) {
        try IAutoCompoundingPodLp(_aspTkn).withdrawProtocolFees() {
            return true;
        } catch {
            return false;
        }
    }
}

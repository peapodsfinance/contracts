// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILeverageFeeProcessor {
    struct PartnerConfig {
        address wallet;
        uint16 openFee; // PRECISION, e.g., 100 = 1%
        uint16 closeFee; // PRECISION, e.g., 100 = 1%
        uint256 expiration; // timestamp when the partner will no longer receive fees
    }

    function processFees(address _pod, address _tkn, uint256 _totalFees, address _mainFeeReceiver, bool _isOpen)
        external;
}

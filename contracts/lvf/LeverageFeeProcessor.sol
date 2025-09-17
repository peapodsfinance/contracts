// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILeverageFeeProcessor} from "../interfaces/ILeverageFeeProcessor.sol";

contract LeverageFeeProcessor is ILeverageFeeProcessor, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Used in calculations for various fees and percentage calculations
    uint16 constant PRECISION = 10000;

    /// @dev pod => partner conf
    mapping(address => PartnerConfig) public partner;

    /// @notice insurance wallet to receive open/close fees
    address public insurance;
    uint16 public insuranceFee; // PRECISION, e.g., 100 = 1%

    event SetPartnerConfig(
        address pod, address partner, uint16 partnerFeeOpen, uint16 partnerFeeClose, uint256 partnerExpiration
    );

    event SetInsuranceConfig(address insuranceAddress, uint16 feePercent);

    constructor() Ownable(msg.sender) {}

    function processFees(address _pod, address _tkn, uint256 _totalFees, address _mainFeeReceiver, bool _isOpen)
        external
    {
        address _partner = partner[_pod].wallet;
        uint256 _expiration = partner[_pod].expiration;
        uint16 _partnerFeePerc = _isOpen ? partner[_pod].openFee : partner[_pod].closeFee;
        uint256 _treasuryFees = _totalFees;
        if (_partner != address(0) && _partnerFeePerc > 0 && (_expiration == 0 || _expiration > block.timestamp)) {
            uint256 _partnerAmt = (_totalFees * _partnerFeePerc) / PRECISION;
            IERC20(_tkn).safeTransfer(_partner, _partnerAmt);
            _treasuryFees -= _partnerAmt;
        }
        if (insurance != address(0) && insuranceFee > 0) {
            uint256 _insAmt = (_totalFees * insuranceFee) / PRECISION;
            IERC20(_tkn).safeTransfer(insurance, _insAmt);
            _treasuryFees -= _insAmt;
        }
        IERC20(_tkn).safeTransfer(_mainFeeReceiver, _treasuryFees);
    }

    /// @notice Set partner configuration for a given pod from fees
    function setPartnerConfig(
        address _pod,
        address _partner,
        uint16 _partnerFeeOpen,
        uint16 _partnerFeeClose,
        uint256 _partnerExpiration
    ) external onlyOwner {
        require(_partnerFeeOpen <= 6000, "M1");
        require(_partnerFeeClose <= 6000, "M2");
        partner[_pod].wallet = _partner;
        partner[_pod].openFee = _partnerFeeOpen;
        partner[_pod].closeFee = _partnerFeeClose;
        partner[_pod].expiration = _partnerExpiration;
        emit SetPartnerConfig(_pod, _partner, _partnerFeeOpen, _partnerFeeClose, _partnerExpiration);
    }

    /// @notice Set insurance fund configuration from fees
    function setInsuranceConfig(address _insuranceAddress, uint16 _insuranceFee) external onlyOwner {
        require(_insuranceFee <= 2500, "M");
        insurance = _insuranceAddress;
        insuranceFee = _insuranceFee;
        emit SetInsuranceConfig(_insuranceAddress, _insuranceFee);
    }

    /// @notice Emergency function to rescue ERC20 tokens from the contract
    function rescueTokens(IERC20 _token) external onlyOwner {
        _token.safeTransfer(msg.sender, _token.balanceOf(address(this)));
    }
}

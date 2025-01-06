// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../contracts/interfaces/IFlashLoanRecipient.sol";
import "../../../contracts/interfaces/IFlashLoanSource.sol";

contract FlashSourceReceiverTest is IFlashLoanRecipient {
    using SafeERC20 for IERC20;

    function tryFlash(IFlashLoanSource _source, address _token, uint256 _amount) external {
        uint256 _extraPayment = _source.paymentAmount();
        if (_extraPayment > 0) {
            address _extraToken = _source.paymentToken();
            IERC20(_extraToken).safeTransferFrom(msg.sender, address(this), _extraPayment);
            IERC20(_extraToken).safeIncreaseAllowance(address(_source), _extraPayment);
        }
        bytes memory _data = abi.encode(address(_source));
        _source.flash(_token, _amount, address(this), _data);
    }

    function callback(bytes memory _data) external override {
        IFlashLoanSource.FlashData memory _parsedData = abi.decode(_data, (IFlashLoanSource.FlashData));
        address _source = abi.decode(_parsedData.data, (address));
        require(msg.sender == _source, "SRC");
        IERC20(_parsedData.token).safeTransfer(
            IFlashLoanSource(msg.sender).source(), _parsedData.amount + _parsedData.fee
        );
    }
}

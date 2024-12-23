// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IDecentralizedIndex.sol";
import "../interfaces/IFlashLoanRecipient.sol";
import "./FlashSourceBase.sol";

contract PodFlashSource is FlashSourceBase, IFlashLoanRecipient {
    using SafeERC20 for IERC20;

    address public immutable override source;
    address public immutable override paymentToken;

    constructor(address _pod, address _flashPaymentToken, address _lvfMan) FlashSourceBase(_lvfMan) {
        source = _pod;
        paymentToken = _flashPaymentToken;
    }

    function paymentAmount() public view returns (uint256) {
        return IDecentralizedIndex(source).FLASH_FEE_AMOUNT_DAI();
    }

    function flash(address _token, uint256 _amount, address _recipient, bytes calldata _data)
        external
        override
        workflow(true)
        onlyLeverageManager
    {
        uint256 _paymentAmount = paymentAmount();
        IERC20(paymentToken).safeTransferFrom(_msgSender(), address(this), _paymentAmount);
        IERC20(paymentToken).safeIncreaseAllowance(source, _paymentAmount);
        FlashData memory _fData = FlashData(_recipient, _token, _amount, _data, 0);
        IDecentralizedIndex(source).flash(address(this), _token, _amount, abi.encode(_fData));
    }

    function callback(bytes calldata _data) external override workflow(false) {
        require(_msgSender() == source, "CBV");
        FlashData memory _fData = abi.decode(_data, (FlashData));
        IERC20(_fData.token).safeTransfer(_fData.recipient, _fData.amount);
        IFlashLoanRecipient(_fData.recipient).callback(_data);
    }
}

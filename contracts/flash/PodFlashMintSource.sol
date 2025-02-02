// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IDecentralizedIndex.sol";
import "../interfaces/IFlashLoanRecipient.sol";
import "./FlashSourceBase.sol";

contract PodFlashMintSource is FlashSourceBase, IFlashLoanRecipient {
    using SafeERC20 for IERC20;

    address public immutable override source;
    address public immutable override paymentToken;
    uint256 public immutable override paymentAmount;

    constructor(address _pod, address _lvfMan) FlashSourceBase(_lvfMan) {
        source = _pod;
    }

    function flash(address, uint256 _amount, address _recipient, bytes calldata _data)
        external
        override
        workflow(true)
        onlyLeverageManager
    {
        uint256 _feeAmt = _amount / 1000 > 0 ? _amount / 1000 : 1;
        FlashData memory _fData = FlashData(_recipient, source, _amount, _data, _feeAmt);
        IDecentralizedIndex(source).flashMint(address(this), _amount, abi.encode(_fData));
    }

    function callback(bytes calldata _data) external override workflow(false) {
        require(_msgSender() == source, "CBV");
        FlashData memory _fData = abi.decode(_data, (FlashData));
        IERC20(_fData.token).safeTransfer(_fData.recipient, _fData.amount);
        IFlashLoanRecipient(_fData.recipient).callback(_data);
    }
}

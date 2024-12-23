// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IFlashLoanRecipient.sol";
import "./FlashSourceBase.sol";

interface IBalancerFlashRecipient {
    function receiveFlashLoan(IERC20[] memory, uint256[] memory, uint256[] memory _feeAmounts, bytes memory _userData)
        external;
}

interface IBalancerVault {
    function flashLoan(
        IBalancerFlashRecipient recipient,
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

// https://docs.balancer.fi/reference/contracts/flash-loans.html#example-code
contract BalancerFlashSource is FlashSourceBase, IBalancerFlashRecipient {
    using SafeERC20 for IERC20;

    address public override source = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public override paymentToken;
    uint256 public override paymentAmount;

    constructor(address _lvfMan) FlashSourceBase(_lvfMan) {}

    function flash(address _token, uint256 _amount, address _recipient, bytes calldata _data)
        external
        override
        workflow(true)
        onlyLeverageManager
    {
        IERC20[] memory _tokens = new IERC20[](1);
        uint256[] memory _amounts = new uint256[](1);
        _tokens[0] = IERC20(_token);
        _amounts[0] = _amount;
        FlashData memory _fData = FlashData(_recipient, _token, _amount, _data, 0);
        IBalancerVault(source).flashLoan(this, _tokens, _amounts, abi.encode(_fData));
    }

    function receiveFlashLoan(IERC20[] memory, uint256[] memory, uint256[] memory _feeAmounts, bytes memory _userData)
        external
        override
        workflow(false)
    {
        require(_msgSender() == source, "CBV");
        FlashData memory _fData = abi.decode(_userData, (FlashData));
        _fData.fee = _feeAmounts[0];
        IERC20(_fData.token).safeTransfer(_fData.recipient, _fData.amount);
        IFlashLoanRecipient(_fData.recipient).callback(_userData);
    }
}

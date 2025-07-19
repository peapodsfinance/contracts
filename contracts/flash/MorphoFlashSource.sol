// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IFlashLoanRecipient.sol";
import "./FlashSourceBase.sol";

interface IMorphoVault {
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
}

interface IMorphoFlashLoanCallback {
    function onMorphoFlashLoan(uint256 assets, bytes memory userData) external;
}

contract MorphoFlashSource is FlashSourceBase, IMorphoFlashLoanCallback {
    using SafeERC20 for IERC20;

    address public override source;
    address public override paymentToken;
    uint256 public override paymentAmount;

    constructor(address _lvfMan, address _morphoVault) FlashSourceBase(_lvfMan) {
        source = _morphoVault;
    }

    function flash(address _token, uint256 _amount, address _recipient, bytes calldata _data)
        external
        override
        workflow(true)
        onlyLeverageManager
    {
        IMorphoVault(source).flashLoan(_token, _amount, abi.encode(FlashData(_recipient, _token, _amount, _data, 0)));
    }

    function onMorphoFlashLoan(uint256, bytes memory _userData) external override workflow(false) {
        require(_msgSender() == source, "CBV");
        FlashData memory _fData = abi.decode(_userData, (FlashData));
        IERC20(_fData.token).safeTransfer(_fData.recipient, _fData.amount);
        IFlashLoanRecipient(_fData.recipient).callback(abi.encode(_fData));
    }
}

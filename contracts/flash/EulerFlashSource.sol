// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IFlashLoanRecipient.sol";
import "./FlashSourceBase.sol";

interface IEulerVault {
    function flashLoan(uint256 amount, bytes calldata data) external;
}

interface IEuelerVaultReceiver {
    function onFlashLoan(bytes memory userData) external;
}

contract EulerFlashSource is FlashSourceBase, IEuelerVaultReceiver {
    using SafeERC20 for IERC20;

    address public override source;
    address public override paymentToken;
    uint256 public override paymentAmount;

    constructor(address _lvfMan, address _eulerVault) FlashSourceBase(_lvfMan) {
        source = _eulerVault;
    }

    function flash(address _token, uint256 _amount, address _recipient, bytes calldata _data)
        external
        override
        workflow(true)
        onlyLeverageManager
    {
        IEulerVault(source).flashLoan(_amount, abi.encode(FlashData(_recipient, _token, _amount, _data, 0)));
    }

    function onFlashLoan(bytes memory _userData) external override workflow(false) {
        require(_msgSender() == source, "CBV");
        FlashData memory _fData = abi.decode(_userData, (FlashData));
        IERC20(_fData.token).safeTransfer(_fData.recipient, _fData.amount);
        IFlashLoanRecipient(_fData.recipient).callback(abi.encode(_fData));
    }
}

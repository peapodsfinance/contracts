// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../contracts/interfaces/IFlashLoanRecipient.sol";

contract MockFlashMintRecipient is IFlashLoanRecipient {
    bool public shouldRevert;
    bool public shouldTransfer;
    address public transferTo;
    uint256 public transferAmount;
    bytes public lastCallbackData;

    function setRevertFlag(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setTransferParams(bool _shouldTransfer, address _to, uint256 _amount) external {
        shouldTransfer = _shouldTransfer;
        transferTo = _to;
        transferAmount = _amount;
    }

    function callback(bytes calldata _data) external override {
        lastCallbackData = _data;

        if (shouldRevert) {
            revert("MockFlashMintRecipient: forced revert");
        }

        if (shouldTransfer && transferTo != address(0)) {
            IERC20(msg.sender).transfer(transferTo, transferAmount);
        }
    }
}

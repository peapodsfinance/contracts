// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../contracts/interfaces/IFlashLoanRecipient.sol";
import "../../contracts/interfaces/IFlashLoanSource.sol";

contract MockFlashMintRecipient is IFlashLoanRecipient {
    bool public shouldRevert;
    bool public shouldUseShource;
    bytes public lastCallbackData;

    function setRevertFlag(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setShouldUseShource(bool _shouldUseShource) external {
        shouldUseShource = _shouldUseShource;
    }

    function callback(bytes calldata _data) external override {
        // Store just the data portion from the flash data
        IFlashLoanSource.FlashData memory flashData = abi.decode(_data, (IFlashLoanSource.FlashData));
        lastCallbackData = flashData.data;

        if (shouldRevert) {
            revert("MockFlashMintRecipient: forced revert");
        }

        // Transfer the flash minted tokens back to the pod
        IERC20(flashData.token).transfer(
            shouldUseShource ? IFlashLoanSource(msg.sender).source() : msg.sender, flashData.amount + flashData.fee
        );
    }
}

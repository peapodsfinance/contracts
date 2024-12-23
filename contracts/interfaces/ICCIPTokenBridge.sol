// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICCIPTokenBridge {
    struct TokenTransfer {
        address tokenReceiver;
        address targetToken;
        uint256 amount;
    }

    event TokensSent(
        bytes32 indexed messageId,
        uint64 indexed chainSelector,
        address receiver,
        address token,
        uint256 amountDesired,
        uint256 amountActual,
        uint256 fees
    );

    event TokensReceived(
        bytes32 indexed messageId, uint64 indexed chainSelector, address receiver, address token, uint256 amount
    );
}

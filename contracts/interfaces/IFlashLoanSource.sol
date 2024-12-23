// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IFlashLoanSource {
    struct FlashData {
        address recipient;
        address token;
        uint256 amount;
        bytes data;
        uint256 fee;
    }

    function source() external view returns (address);

    function paymentToken() external view returns (address);

    function paymentAmount() external view returns (uint256);

    function flash(address token, uint256 amount, address recipient, bytes calldata data) external;
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

interface ICamelotRouter {
    function factory() external view returns (address);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        address referrer,
        uint256 deadline
    ) external;
}

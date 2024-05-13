// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2;

interface ICamelotRouter {
  function factory() external view returns (address);

  function swapExactTokensForTokensSupportingFeeOnTransferTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    address referrer,
    uint deadline
  ) external;
}

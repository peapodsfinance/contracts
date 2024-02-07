// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC4626 {
  function deposit(
    uint256 yETHAmount,
    address receiver
  ) external returns (uint256 styETHAmount);

  function withdraw(
    uint256 styETHAmount,
    address receiver
  ) external returns (uint256 yETHAmount);
}

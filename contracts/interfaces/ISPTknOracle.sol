// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ISPTknOracle {
  function getPodPerBasePrice() external view returns (uint256 _price);
}

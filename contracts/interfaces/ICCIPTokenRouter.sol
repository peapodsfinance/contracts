// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ICCIPTokenRouter {
  struct TokenConfig {
    bool enabled;
    address targetBridge;
    address sourceToken;
    bool sourceTokenMintBurn;
    uint64 targetChain;
    address targetToken;
  }

  function globalEnabled() external view returns (bool);

  function targetChainGasLimit() external view returns (uint256);

  function getConfig(
    address sourceToken,
    uint64 chainSelector
  ) external returns (TokenConfig memory);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICCIPTokenRouter {
    struct TokenConfig {
        bool enabled;
        address targetBridge;
        address sourceToken;
        bool sourceTokenMintBurn;
        uint64 targetChain;
        address targetToken;
    }

    event SetConfigEnabled(address indexed wallet, address sourceToken, uint64 targetChain, bool isEnabled);
    event SetGlobalEnabled(address indexed wallet, bool isEnabled);
    event SetTargetGasChainLimit(address indexed wallet, uint256 newLimit);

    function globalEnabled() external view returns (bool);

    function targetChainGasLimit() external view returns (uint256);

    function getConfig(address sourceToken, uint64 chainSelector) external returns (TokenConfig memory);
}

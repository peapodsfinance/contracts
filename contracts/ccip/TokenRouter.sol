// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ICCIPTokenRouter.sol";

contract TokenRouter is ICCIPTokenRouter, Ownable {
    bool public override globalEnabled = true;
    uint256 public override targetChainGasLimit = 200_000;

    // source token => target chain selector => config
    mapping(address => mapping(uint64 => TokenConfig)) _configs;

    constructor() Ownable(_msgSender()) {}

    function getConfig(address _sourceToken, uint64 _targetChainSelector)
        external
        view
        override
        returns (TokenConfig memory)
    {
        return _configs[_sourceToken][_targetChainSelector];
    }

    function setConfig(
        address _targetBridge,
        uint64 _targetChain,
        address _sourceToken,
        bool _sourceTokenMintBurn,
        address _targetToken,
        bool _enabled
    ) external onlyOwner {
        _configs[_sourceToken][_targetChain] = TokenConfig({
            enabled: _enabled,
            targetBridge: _targetBridge,
            sourceToken: _sourceToken,
            sourceTokenMintBurn: _sourceTokenMintBurn,
            targetChain: _targetChain,
            targetToken: _targetToken
        });
    }

    function setTargetChainGasLimit(uint256 _gasLimit) external onlyOwner {
        require(targetChainGasLimit != _gasLimit, "CHANGE");
        targetChainGasLimit = _gasLimit;
        emit SetTargetGasChainLimit(_msgSender(), _gasLimit);
    }

    function toggleConfigEnabled(address _sourceToken, uint64 _targetChain, bool _isEnabled) external onlyOwner {
        require(_configs[_sourceToken][_targetChain].enabled != _isEnabled);
        _configs[_sourceToken][_targetChain].enabled = _isEnabled;
        emit SetConfigEnabled(_msgSender(), _sourceToken, _targetChain, _isEnabled);
    }

    function toggleGlobalEnabled(bool _isEnabled) external onlyOwner {
        require(globalEnabled != _isEnabled);
        globalEnabled = _isEnabled;
        emit SetGlobalEnabled(_msgSender(), _isEnabled);
    }
}

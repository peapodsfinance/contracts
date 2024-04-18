// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import './interfaces/IRewardsWhitelister.sol';

contract RewardsWhitelist is IRewardsWhitelister, Ownable {
  mapping(address => bool) public override whitelist;

  function toggleRewardsToken(
    address _token,
    bool _isWhitelisted
  ) external onlyOwner {
    require(whitelist[_token] != _isWhitelisted, 'OPP');
    whitelist[_token] = _isWhitelisted;
  }
}

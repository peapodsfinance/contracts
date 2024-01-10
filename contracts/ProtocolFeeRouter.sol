// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import './interfaces/IProtocolFees.sol';
import './interfaces/IProtocolFeeRouter.sol';

contract ProtocolFeeRouter is IProtocolFeeRouter, Ownable {
  IProtocolFees public override protocolFees;

  constructor(IProtocolFees _fees) {
    protocolFees = _fees;
  }

  function setProtocolFees(IProtocolFees _protocolFees) external onlyOwner {
    protocolFees = _protocolFees;
  }
}

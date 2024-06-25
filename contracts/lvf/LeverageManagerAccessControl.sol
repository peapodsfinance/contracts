// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '../interfaces/IFlashLoanSource.sol';
import '../interfaces/IFraxlendPair.sol';

contract LeverageManagerAccessControl is Ownable {
  // pod => pair
  mapping(address => address) public lendingPairs;
  // pod => auto compounding LP token
  mapping(address => address) public aspTkn;
  // pod => flash source
  mapping(address => address) public flashSource;

  function setPair(address _pod, address _pair) external onlyOwner {
    if (_pair != address(0)) {
      require(IFraxlendPair(_pair).collateralContract() != address(0), 'AV');
    }
    lendingPairs[_pod] = _pair;
  }

  function setAspTkn(address _pod, address _lpCompToken) external onlyOwner {
    aspTkn[_pod] = _lpCompToken;
  }

  function setFlashSource(
    address _pod,
    address _flashSource
  ) external onlyOwner {
    if (_flashSource != address(0)) {
      require(IFlashLoanSource(_flashSource).source() != address(0), 'AFS');
    }
    flashSource[_pod] = _flashSource;
  }
}

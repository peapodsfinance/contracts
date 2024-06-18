// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '../interfaces/IFlashLoanSource.sol';
import '../interfaces/IFraxlendPair.sol';

contract LeverageManagerAccessControl is Ownable {
  // pod => pair
  mapping(address => address) public lendingPairs;
  // pod => auto compounding LP token
  mapping(address => address) public lpCompounder;
  // pod => flash source
  mapping(address => address) public flashSource;

  function addPair(address _pod, address _pair) external onlyOwner {
    require(lendingPairs[_pod] == address(0), 'A');
    require(IFraxlendPair(_pair).collateralContract() != address(0), 'AV');
    lendingPairs[_pod] = _pair;
  }

  function removePair(address _pod) external onlyOwner {
    require(lendingPairs[_pod] != address(0), 'R');
    delete lendingPairs[_pod];
  }

  function addLpCompound(
    address _pod,
    address _lpCompToken
  ) external onlyOwner {
    require(lpCompounder[_pod] == address(0), 'A');
    lpCompounder[_pod] = _lpCompToken;
  }

  function removeLpCompound(address _pod) external onlyOwner {
    require(lpCompounder[_pod] != address(0), 'R');
    delete lpCompounder[_pod];
  }

  function addFlashSource(
    address _pod,
    address _flashSource
  ) external onlyOwner {
    require(flashSource[_pod] == address(0), 'A');
    require(IFlashLoanSource(_flashSource).source() != address(0), 'AFS');
    flashSource[_pod] = _flashSource;
  }

  function removeFlashSource(address _pod) external onlyOwner {
    require(flashSource[_pod] != address(0), 'R');
    delete flashSource[_pod];
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '../interfaces/IFlashLoanSource.sol';
import '../interfaces/IFraxlendPair.sol';

contract LeverageManagerAccessControl is Ownable {
  // pod => pair
  mapping(address => address) public lendingPairs;
  // borrow asset (USDC, DAI, pOHM, etc.) => flash source
  mapping(address => address) public flashSource;

  function setLendingPair(address _pod, address _pair) external onlyOwner {
    if (_pair != address(0)) {
      require(IFraxlendPair(_pair).collateralContract() != address(0), 'AV');
    }
    lendingPairs[_pod] = _pair;
  }

  function setFlashSource(
    address _borrowAsset,
    address _flashSource
  ) external onlyOwner {
    if (_flashSource != address(0)) {
      require(IFlashLoanSource(_flashSource).source() != address(0), 'AFS');
    }
    flashSource[_borrowAsset] = _flashSource;
  }
}

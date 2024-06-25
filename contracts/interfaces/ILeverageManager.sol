// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ILeverageManager {
  enum FlashCallbackMethod {
    ADD,
    REMOVE
  }

  struct LeverageFlashProps {
    FlashCallbackMethod method;
    uint256 tokenId;
    address user;
    address pod;
    uint256 podAmount;
    uint256 pairedLpDesired;
    uint256 pairedLpAmtMin;
    uint256 slippage;
    uint256 deadline;
  }

  struct LeveragePositionProps {
    address pod;
    address lendingPair;
    address custodian;
  }

  function initializePosition(address _pod, address _recipient) external;

  function addLeverage(
    uint256 _tokenId,
    address _pod,
    uint256 _podAmount,
    uint256 _pairedLpDesired,
    uint256 _pairedLpAmtMin,
    uint256 _slippage,
    uint256 _deadline
  ) external;

  function removeLeverage(
    uint256 _tokenId,
    uint256 _borrowAssetAmt,
    uint256 _collateralAssetAmtRemove,
    uint256 _podAmtMin,
    uint256 _pairedAssetAmtMin,
    address _dexAdapter,
    uint256 _userProvidedDebtAmtMax
  ) external;
}

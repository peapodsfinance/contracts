// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ILeverageManager {
  enum FlashCallbackMethod {
    ADD,
    REMOVE
  }

  struct LeverageFlashProps {
    FlashCallbackMethod method;
    uint256 positionId;
    address user;
    uint256 pTknAmt;
    uint256 pairedLpDesired;
    uint256 pairedLpAmtMin;
    address selfLendingPairPod;
    bytes config;
  }

  struct LeveragePositionProps {
    address pod;
    address lendingPair;
    address custodian;
    address selfLendingPod;
  }

  function initializePosition(
    address _pod,
    address _recipient,
    address _selfLendingPairPod
  ) external returns (uint256 _positionId);

  function addLeverage(
    uint256 _positionId,
    address _pod,
    uint256 _pTknAmt,
    uint256 _pairedLpDesired,
    uint256 _pairedLpAmtMin,
    address _selfLendingPairPod,
    bytes memory _config
  ) external;

  function removeLeverage(
    uint256 _positionId,
    uint256 _borrowAssetAmt,
    uint256 _collateralAssetAmtRemove,
    uint256 _podAmtMin,
    uint256 _pairedAssetAmtMin,
    address _dexAdapter,
    uint256 _userProvidedDebtAmtMax
  ) external;
}

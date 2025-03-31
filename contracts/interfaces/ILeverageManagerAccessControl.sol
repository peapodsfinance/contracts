// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILeverageManagerAccessControl {
    event SetPodLendingPair(address _pod, address _lendingPair);

    event SetBorrowAssetFlashSource(address _borrowAsset, address _flashSource);

    function lendingPairs(address _pod) external view returns (address _lendingPair);

    function flashSource(address _borrowTkn) external view returns (address _flashSource);

    function setLendingPair(address _pod, address _pair) external;

    function setFlashSource(address _borrowAsset, address _flashSource) external;
}

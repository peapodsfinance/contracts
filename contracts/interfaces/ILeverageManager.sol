// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILeverageManager {
    enum FlashCallbackMethod {
        ADD,
        REMOVE
    }

    struct LeverageFlashProps {
        FlashCallbackMethod method;
        uint256 positionId;
        address owner;
        address sender;
        uint256 pTknAmt;
        uint256 pairedLpDesired;
        bytes config;
    }

    struct LeveragePositionProps {
        address pod;
        address lendingPair;
        address custodian;
        bool isSelfLending;
        bool hasSelfLendingPairPod;
    }

    event AddLeverage(
        uint256 indexed positionId, address indexed user, uint256 pTknAmtUsed, uint256 collateralAmt, uint256 borrowAmt
    );

    event RemoveLeverage(uint256 indexed positionId, address indexed user, uint256 collateralAmt);

    event SetIndexUtils(address oldIdxUtils, address newIdxUtils);

    event SetOpenFeePerc(uint16 oldFee, uint16 newFee);

    event SetCloseFeePerc(uint16 oldFee, uint16 newFee);

    function initializePosition(
        address _pod,
        address _recipient,
        address _overrideLendingPair,
        bool _hasSelfLendingPairPod
    ) external returns (uint256 _positionId);

    function addLeverage(
        uint256 _positionId,
        address _pod,
        uint256 _pTknAmt,
        uint256 _pairedLpDesired,
        uint256 _userProvidedDebtAmt,
        bool _hasSelfLendingPairPod,
        bytes memory _config
    ) external;

    function addLeverageFromTkn(
        uint256 _positionId,
        address _pod,
        uint256 _tknAmt,
        uint256 _amtPtknMintMin,
        uint256 _pairedLpDesired,
        uint256 _userProvidedDebtAmt,
        bool _hasSelfLendingPairPod,
        bytes memory _config
    ) external;

    function removeLeverage(
        uint256 _positionId,
        uint256 _borrowAssetAmt,
        uint256 _collateralAssetAmtRemove,
        uint256 _podAmtMin,
        uint256 _pairedAssetAmtMin,
        uint256 _podSwapAmtOutMin,
        uint256 _userProvidedDebtAmtMax
    ) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/Context.sol';
import '../interfaces/IDecentralizedIndex.sol';
import '../interfaces/IDexAdapter.sol';
import '../interfaces/IFlashLoanRecipient.sol';
import '../interfaces/IIndexUtils.sol';
import '../interfaces/ILeverageManager.sol';
import '../AutoCompoundingPodLp.sol';
import './LeverageManagerAccessControl.sol';
import './LeveragePositions.sol';
import './LeveragePositionCustodian.sol';

contract LeverageManager is
  ILeverageManager,
  IFlashLoanRecipient,
  Context,
  LeverageManagerAccessControl
{
  using SafeERC20 for IERC20;

  IDexAdapter public dexAdapter;
  IIndexUtils public indexUtils;
  LeveragePositions public positionNFT;

  // tokenId => position props
  mapping(uint256 => LeveragePositionProps) public positionProps;

  event AddLeverage(uint256 indexed tokenId, address indexed user);

  modifier onlyPositionOwner(uint256 _tokenId) {
    require(positionNFT.ownerOf(_tokenId) == _msgSender(), 'AUTH');
    _;
  }

  constructor(
    string memory _positionName,
    string memory _positionSymbol,
    IDexAdapter _dexAdapter,
    IIndexUtils _idxUtils
  ) {
    dexAdapter = _dexAdapter;
    indexUtils = _idxUtils;
    positionNFT = new LeveragePositions(_positionName, _positionSymbol);
  }

  function addLeverage(
    uint256 _tokenId,
    address _pod,
    uint256 _podAmount,
    uint256 _pairedLpDesired,
    uint256 _pairedLpAmtMin,
    uint256 _slippage,
    uint256 _deadline
  ) external override {
    require(flashSource[_pod] != address(0), 'FSV');
    require(lendingPairs[_pod] != address(0), 'LVP');
    if (_tokenId > 0) {
      require(positionNFT.ownerOf(_tokenId) == _msgSender(), 'AUTH');
    }

    IFlashLoanSource _flashLoanSource = IFlashLoanSource(flashSource[_pod]);
    IERC20(_pod).safeTransferFrom(_msgSender(), address(this), _podAmount);

    // if additional fees required for flash source, handle that here
    _processExtraFlashLoanPayment(_pod, _msgSender());

    address _pairedLpAsset = IDecentralizedIndex(_pod).PAIRED_LP_TOKEN();

    bytes memory _noop;
    bytes memory _leverageData = abi.encode(
      LeverageFlashProps(
        FlashCallbackMethod.ADD,
        _tokenId,
        _msgSender(),
        _pod,
        _podAmount,
        _pairedLpDesired,
        _pairedLpAmtMin,
        _slippage,
        _deadline
      ),
      _noop
    );
    IFlashLoanSource.FlashData memory _d = IFlashLoanSource.FlashData({
      recipient: address(this),
      token: _pairedLpAsset,
      amount: _pairedLpDesired,
      data: _leverageData,
      fee: 0
    });
    _flashLoanSource.flash(
      _pairedLpAsset,
      _pairedLpDesired,
      address(this),
      abi.encode(_d)
    );
  }

  function removeLeverage(
    uint256 _tokenId,
    uint256 _borrowAssetAmt,
    uint256 _collateralAssetAmtRemove,
    uint256 _podAmtMin,
    uint256 _pairedAssetAmtMin,
    bool _userProvidesRepayDebt
  ) external override onlyPositionOwner(_tokenId) {
    LeveragePositionProps memory _props = positionProps[_tokenId];
    IFlashLoanSource _flashLoanSource = IFlashLoanSource(
      flashSource[_props.pod]
    );

    // if additional fees required for flash source, handle that here
    _processExtraFlashLoanPayment(_props.pod, _msgSender());

    LeverageFlashProps memory _position;
    _position.method = FlashCallbackMethod.REMOVE;
    _position.tokenId = _tokenId;
    _position.user = _msgSender();
    _position.pod = _props.pod;
    bytes memory _additionalInfo = abi.encode(
      _borrowAssetAmt,
      _collateralAssetAmtRemove,
      _podAmtMin,
      _pairedAssetAmtMin,
      _userProvidesRepayDebt
    );
    bytes memory _data = abi.encode(_position, _additionalInfo);

    IFlashLoanSource.FlashData memory _d = IFlashLoanSource.FlashData({
      recipient: address(this),
      token: address(0), // noop
      amount: 0, // noop
      data: _data,
      fee: 0
    });
    _flashLoanSource.flash(
      IDecentralizedIndex(_props.pod).PAIRED_LP_TOKEN(),
      _borrowAssetAmt,
      address(this),
      abi.encode(_d)
    );
  }

  function callback(bytes memory _userData) external override {
    IFlashLoanSource.FlashData memory _d = abi.decode(
      _userData,
      (IFlashLoanSource.FlashData)
    );
    (LeverageFlashProps memory _posProps, ) = abi.decode(
      _d.data,
      (LeverageFlashProps, bytes)
    );

    require(flashSource[_posProps.pod] == _msgSender(), 'AUTH');

    if (_posProps.method == FlashCallbackMethod.ADD) {
      (address _user, address _pod, uint256 _podRefundAmt) = _addLeverage(
        _userData
      );
      if (_podRefundAmt > 0) {
        IERC20(_pod).safeTransfer(_user, _podRefundAmt);
      }
    } else if (_posProps.method == FlashCallbackMethod.REMOVE) {
      (uint256 _podAmtToUser, uint256 _pairedLpToUser) = _removeLeverage(
        _userData
      );
      if (_podAmtToUser > 0) {
        IERC20(_posProps.pod).safeTransfer(_posProps.user, _podAmtToUser);
      }
      if (_pairedLpToUser > 0) {
        IERC20(IDecentralizedIndex(_posProps.pod).PAIRED_LP_TOKEN())
          .safeTransfer(_posProps.user, _pairedLpToUser);
      }
    } else {
      require(false, 'NI');
    }
  }

  function _processExtraFlashLoanPayment(address _pod, address _user) internal {
    IFlashLoanSource _flashLoanSource = IFlashLoanSource(flashSource[_pod]);
    uint256 _flashPaymentAmount = _flashLoanSource.paymentAmount();
    if (_flashPaymentAmount > 0) {
      address _paymentAsset = _flashLoanSource.paymentToken();
      IERC20(_paymentAsset).safeTransferFrom(
        _user,
        address(this),
        _flashPaymentAmount
      );
      IERC20(_paymentAsset).safeIncreaseAllowance(
        flashSource[_pod],
        _flashPaymentAmount
      );
    }
  }

  function _addLeverage(
    bytes memory _data
  ) internal returns (address _user, address _pod, uint256 _refundAmt) {
    IFlashLoanSource.FlashData memory _d = abi.decode(
      _data,
      (IFlashLoanSource.FlashData)
    );
    LeverageFlashProps memory _props;
    uint256 _stakingCollateralBal;
    uint256 _podAmountUsed;
    (_props, _stakingCollateralBal, _podAmountUsed) = _lpAndStakeInPod(_d);
    _pod = _props.pod;
    _user = _props.user;
    _refundAmt = _props.podAmount - _podAmountUsed;
    uint256 _tokenId = _props.tokenId > 0
      ? _props.tokenId
      : positionNFT.mint(_props.user);

    IERC20(IDecentralizedIndex(_pod).lpStakingPool()).safeIncreaseAllowance(
      lendingPairs[_pod],
      _stakingCollateralBal
    );

    LeveragePositionCustodian _custodian = _props.tokenId > 0
      ? LeveragePositionCustodian(positionProps[_tokenId].custodian)
      : new LeveragePositionCustodian();
    IFraxlendPair(lendingPairs[_pod]).borrowAsset(
      _props.pairedLpDesired,
      _stakingCollateralBal,
      address(_custodian)
    );
    uint256 _borrowedBefore = IERC20(_d.token).balanceOf(address(this));
    _custodian.withdraw(_d.token, address(this), 0);
    uint256 _borrowedAvailable = IERC20(_d.token).balanceOf(address(this)) -
      _borrowedBefore;

    // pay back flash loan and send remaining to borrower
    uint256 _flashPaybackAmt = _d.amount + _d.fee;
    IERC20(_d.token).safeTransfer(
      IFlashLoanSource(flashSource[_pod]).source(),
      _flashPaybackAmt
    );
    if (_borrowedAvailable - _flashPaybackAmt > 0) {
      IERC20(_d.token).safeTransfer(
        _user,
        _borrowedAvailable - _flashPaybackAmt
      );
    }

    positionProps[_tokenId] = LeveragePositionProps({
      pod: _pod,
      lendingPair: lendingPairs[_pod],
      custodian: address(_custodian)
    });
    emit AddLeverage(_tokenId, _user);
  }

  function _removeLeverage(
    bytes memory _userData
  ) internal returns (uint256 _podAmtRemaining, uint256 _borrowAmtRemaining) {
    IFlashLoanSource.FlashData memory _d = abi.decode(
      _userData,
      (IFlashLoanSource.FlashData)
    );
    (LeverageFlashProps memory _props, bytes memory _additionalInfo) = abi
      .decode(_d.data, (LeverageFlashProps, bytes));
    (
      uint256 _borrowAssetAmt,
      uint256 _collateralAssetAmtRemove,
      uint256 _podAmtMin,
      uint256 _pairedAssetAmtMin,
      bool _userProvidesRepayDebt
    ) = abi.decode(_additionalInfo, (uint256, uint256, uint256, uint256, bool));

    LeveragePositionCustodian _custodian = LeveragePositionCustodian(
      positionProps[_props.tokenId].custodian
    );
    IFraxlendPair(lendingPairs[_props.pod]).repayAsset(
      _borrowAssetAmt,
      address(_custodian)
    );
    _custodian.removeCollateral(
      lendingPairs[_props.pod],
      _collateralAssetAmtRemove,
      address(this)
    );
    (uint256 _podAmtReceived, uint256 _borrowAmtReceived) = _unstakeAndRemoveLP(
      _props.pod,
      _collateralAssetAmtRemove,
      _podAmtMin,
      _pairedAssetAmtMin
    );

    // pay back flash loan and send remaining to borrower
    uint256 _repayAmount = _d.amount + _d.fee;
    if (_borrowAmtReceived < _repayAmount) {
      if (_userProvidesRepayDebt) {
        IERC20(_d.token).safeTransferFrom(
          _props.user,
          address(this),
          _repayAmount - _borrowAmtReceived
        );
      } else {
        // sell pod token into LP for enough borrow token to get enough to repay
        _swapPodForBorrowToken(
          _props.pod,
          _d.token,
          _podAmtReceived,
          _repayAmount - _borrowAmtReceived
        );
      }
    }
    IERC20(_d.token).safeTransfer(
      IFlashLoanSource(flashSource[_props.pod]).source(),
      _repayAmount
    );
    return (_podAmtReceived, _borrowAmtRemaining - _repayAmount);
  }

  function _swapPodForBorrowToken(
    address _sourceToken,
    address _targetToken,
    uint256 _sourceAmt,
    uint256 _targetNeededAmt
  ) internal returns (uint256 _podRemainingAmt) {
    uint256 _balBefore = IERC20(_sourceToken).balanceOf(address(this));
    dexAdapter.swapV2SingleExactOut(
      _sourceToken,
      _targetToken,
      _sourceAmt,
      _targetNeededAmt,
      address(this)
    );
    _podRemainingAmt =
      _sourceAmt -
      (_balBefore - IERC20(_sourceToken).balanceOf(address(this)));
  }

  function _lpAndStakeInPod(
    IFlashLoanSource.FlashData memory _d
  )
    internal
    returns (
      LeverageFlashProps memory _props,
      uint256 _newStakes,
      uint256 _podAmountUsed
    )
  {
    _props = abi.decode(_d.data, (LeverageFlashProps));

    uint256 _stakeBalBefore = IERC20(
      IDecentralizedIndex(_props.pod).lpStakingPool()
    ).balanceOf(address(this));
    uint256 _podBalBefore = IERC20(_props.pod).balanceOf(address(this));
    IERC20(_props.pod).safeIncreaseAllowance(
      address(indexUtils),
      _props.podAmount
    );
    IERC20(_d.token).safeIncreaseAllowance(
      address(indexUtils),
      _props.pairedLpDesired
    );
    indexUtils.addLPAndStake(
      IDecentralizedIndex(_props.pod),
      _props.podAmount,
      _d.token,
      _d.amount, // == _props.pairedLpDesired
      _props.pairedLpAmtMin,
      _props.slippage,
      _props.deadline
    );
    _podAmountUsed =
      _podBalBefore -
      IERC20(_props.pod).balanceOf(address(this));
    _newStakes =
      IERC20(IDecentralizedIndex(_props.pod).lpStakingPool()).balanceOf(
        address(this)
      ) -
      _stakeBalBefore;
  }

  function _unstakeAndRemoveLP(
    address _pod,
    uint256 _collateralAssetAmtRemove,
    uint256 _podAmtMin,
    uint256 _pairedAssetAmtMin
  ) internal returns (uint256 _podAmtReceived, uint256 _borrowAmtReceived) {
    address _stakingToken = IDecentralizedIndex(_pod).lpStakingPool();
    address _pairedLpToken = IDecentralizedIndex(_pod).PAIRED_LP_TOKEN();

    uint256 _podAmtBefore = IERC20(_pod).balanceOf(address(this));
    uint256 _pairedTokenAmtBefore = IERC20(_pairedLpToken).balanceOf(
      address(this)
    );
    IERC20(_stakingToken).safeIncreaseAllowance(
      address(indexUtils),
      _collateralAssetAmtRemove
    );
    indexUtils.unstakeAndRemoveLP(
      IDecentralizedIndex(_pod),
      _collateralAssetAmtRemove,
      _podAmtMin,
      _pairedAssetAmtMin,
      block.timestamp
    );
    _podAmtReceived = IERC20(_pod).balanceOf(address(this)) - _podAmtBefore;
    _borrowAmtReceived =
      IERC20(_pairedLpToken).balanceOf(address(this)) -
      _pairedTokenAmtBefore;
  }

  function setIndexUtils(IIndexUtils _utils) external onlyOwner {
    indexUtils = _utils;
  }
}

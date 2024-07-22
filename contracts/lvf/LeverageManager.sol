// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/interfaces/IERC4626.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/Context.sol';
import '../interfaces/IDecentralizedIndex.sol';
import '../interfaces/IDexAdapter.sol';
import '../interfaces/IFlashLoanRecipient.sol';
// import '../interfaces/IIndexUtils.sol';
import '../interfaces/IIndexUtils_LEGACY.sol';
import '../interfaces/ILeverageManager.sol';
import { VaultAccount, VaultAccountingLibrary } from '../libraries/VaultAccount.sol';
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
  using VaultAccountingLibrary for VaultAccount;

  IIndexUtils_LEGACY public indexUtils;
  LeveragePositions public positionNFT;

  // positionId => position props
  mapping(uint256 => LeveragePositionProps) public positionProps;

  event AddLeverage(uint256 indexed positionId, address indexed user);

  modifier onlyPositionOwner(uint256 _positionId) {
    require(positionNFT.ownerOf(_positionId) == _msgSender(), 'AUTH');
    _;
  }

  constructor(
    string memory _positionName,
    string memory _positionSymbol,
    IIndexUtils_LEGACY _idxUtils
  ) {
    indexUtils = _idxUtils;
    positionNFT = new LeveragePositions(_positionName, _positionSymbol);
  }

  function initializePosition(
    address _pod,
    address _recipient
  ) external override {
    _initializePosition(_pod, _recipient);
  }

  function addLeverage(
    uint256 _positionId,
    address _pod,
    uint256 _podAmount,
    uint256 _pairedLpDesired,
    uint256 _pairedLpAmtMin,
    uint256 _slippage,
    uint256 _deadline
  ) external override {
    if (_positionId == 0) {
      _positionId = _initializePosition(_pod, _msgSender());
    } else {
      address _msgSender = msg.sender;
      address _owner = positionNFT.ownerOf(_positionId);
      address _approvedAddress = positionNFT.getApproved(_positionId);
      bool _isApprovedAll = positionNFT.isApprovedForAll(_owner, _msgSender);
      require(
        _owner == _msgSender ||
          _approvedAddress == _msgSender ||
          _isApprovedAll,
        'AUTH'
      );
      _pod = positionProps[_positionId].pod;
      require(_pod != address(0), 'PV');
    }
    require(flashSource[_pod] != address(0), 'FSV');
    require(lendingPairs[_pod] != address(0), 'LVP');

    IFlashLoanSource _flashLoanSource = IFlashLoanSource(flashSource[_pod]);
    IERC20(_pod).safeTransferFrom(_msgSender(), address(this), _podAmount);

    // if additional fees required for flash source, handle that here
    _processExtraFlashLoanPayment(_pod, _msgSender());

    address _pairedLpAsset = IDecentralizedIndex(_pod).PAIRED_LP_TOKEN();

    bytes memory _noop;
    bytes memory _leverageData = abi.encode(
      LeverageFlashProps({
        method: FlashCallbackMethod.ADD,
        positionId: _positionId,
        user: _msgSender(),
        pod: _pod,
        podAmount: _podAmount,
        pairedLpDesired: _pairedLpDesired,
        pairedLpAmtMin: _pairedLpAmtMin,
        slippage: _slippage,
        deadline: _deadline
      }),
      _noop
    );
    _flashLoanSource.flash(
      _pairedLpAsset,
      _pairedLpDesired,
      address(this),
      _leverageData
    );
  }

  function removeLeverage(
    uint256 _positionId,
    uint256 _borrowAssetAmt,
    uint256 _collateralAssetAmtRemove,
    uint256 _podAmtMin,
    uint256 _pairedAssetAmtMin,
    address _dexAdapter,
    uint256 _userProvidedDebtAmtMax
  ) external override onlyPositionOwner(_positionId) {
    LeveragePositionProps memory _props = positionProps[_positionId];
    IFlashLoanSource _flashLoanSource = IFlashLoanSource(
      flashSource[_props.pod]
    );

    // if additional fees required for flash source, handle that here
    _processExtraFlashLoanPayment(_props.pod, _msgSender());

    uint256 _borrowSharesToRepay = IFraxlendPair(lendingPairs[_props.pod])
      .totalBorrow()
      .toShares(_borrowAssetAmt, true);

    LeverageFlashProps memory _position;
    _position.method = FlashCallbackMethod.REMOVE;
    _position.positionId = _positionId;
    _position.user = _msgSender();
    _position.pod = _props.pod;
    bytes memory _additionalInfo = abi.encode(
      _borrowSharesToRepay,
      _collateralAssetAmtRemove,
      _podAmtMin,
      _pairedAssetAmtMin,
      _dexAdapter,
      _userProvidedDebtAmtMax
    );
    _flashLoanSource.flash(
      IDecentralizedIndex(_props.pod).PAIRED_LP_TOKEN(),
      _borrowAssetAmt,
      address(this),
      abi.encode(_position, _additionalInfo)
    );
  }

  function withdrawAssets(
    uint256 _positionId,
    address _token,
    address _recipient,
    uint256 _amount
  ) external onlyPositionOwner(_positionId) {
    LeveragePositionCustodian(positionProps[_positionId].custodian).withdraw(
      _token,
      _recipient,
      _amount
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
      uint256 _podRefundAmt = _addLeverage(_userData);
      if (_podRefundAmt > 0) {
        IERC20(_posProps.pod).safeTransfer(_posProps.user, _podRefundAmt);
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

  function _initializePosition(
    address _pod,
    address _recipient
  ) internal returns (uint256 _positionId) {
    require(lendingPairs[_pod] != address(0), 'LVP');
    _positionId = positionNFT.mint(_recipient);
    LeveragePositionCustodian _custodian = new LeveragePositionCustodian();
    positionProps[_positionId] = LeveragePositionProps({
      pod: _pod,
      lendingPair: lendingPairs[_pod],
      custodian: address(_custodian)
    });
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
  ) internal returns (uint256 _refundAmt) {
    IFlashLoanSource.FlashData memory _d = abi.decode(
      _data,
      (IFlashLoanSource.FlashData)
    );
    (LeverageFlashProps memory _props, ) = abi.decode(
      _d.data,
      (LeverageFlashProps, bytes)
    );
    (uint256 _aspTknCollateralBal, uint256 _podAmountUsed, ) = _lpAndStakeInPod(
      IDecentralizedIndex(_props.pod).lpStakingPool(),
      _d,
      _props
    );
    _refundAmt = _props.podAmount - _podAmountUsed;

    IERC20(aspTkn[_props.pod]).safeTransfer(
      positionProps[_props.positionId].custodian,
      _aspTknCollateralBal
    );
    LeveragePositionCustodian(positionProps[_props.positionId].custodian)
      .borrowAsset(
        lendingPairs[_props.pod],
        _props.pairedLpDesired,
        _aspTknCollateralBal,
        address(this)
      );

    // pay back flash loan and send remaining to borrower
    uint256 _flashPaybackAmt = _d.amount + _d.fee;
    IERC20(_d.token).safeTransfer(
      IFlashLoanSource(flashSource[_props.pod]).source(),
      _flashPaybackAmt
    );
    uint256 _remaining = IERC20(_d.token).balanceOf(address(this));
    if (_remaining != 0) {
      IERC20(_d.token).safeTransfer(_props.user, _remaining);
    }
    emit AddLeverage(_props.positionId, _props.user);
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
      uint256 _borrowSharesToRepay,
      uint256 _collateralAssetAmtRemove,
      uint256 _podAmtMin,
      uint256 _pairedAssetAmtMin,
      address _dexAdapter,
      uint256 _userProvidedDebtAmtMax
    ) = abi.decode(
        _additionalInfo,
        (uint256, uint256, uint256, uint256, address, uint256)
      );
    IERC20(_d.token).safeIncreaseAllowance(
      lendingPairs[_props.pod],
      _borrowSharesToRepay
    );
    IFraxlendPair _fraxPair = IFraxlendPair(lendingPairs[_props.pod]);
    _fraxPair.repayAsset(
      _borrowSharesToRepay,
      positionProps[_props.positionId].custodian
    );
    LeveragePositionCustodian(positionProps[_props.positionId].custodian)
      .removeCollateral(
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
    _podAmtRemaining = _podAmtReceived;

    // pay back flash loan and send remaining to borrower
    uint256 _repayAmount = _d.amount + _d.fee;
    if (_borrowAmtReceived < _repayAmount) {
      _podAmtRemaining = _acquireBorrowTokenForRepayment(
        _props.pod,
        _props.user,
        _d.token,
        _dexAdapter,
        _repayAmount,
        _borrowAmtReceived,
        _podAmtReceived,
        _userProvidedDebtAmtMax
      );
    }
    IERC20(_d.token).safeTransfer(
      IFlashLoanSource(flashSource[_props.pod]).source(),
      _repayAmount
    );
    _borrowAmtRemaining = _borrowAmtReceived > _repayAmount
      ? _borrowAmtReceived - _repayAmount
      : 0;
  }

  function _acquireBorrowTokenForRepayment(
    address _pod,
    address _user,
    address _borrowToken,
    address _dexAdapter,
    uint256 _repayAmount,
    uint256 _borrowAmtReceived,
    uint256 _podAmtReceived,
    uint256 _userProvidedDebtAmtMax
  ) internal returns (uint256 _podAmtRemaining) {
    _podAmtRemaining = _podAmtReceived;
    uint256 _borrowNeeded = _repayAmount - _borrowAmtReceived;
    uint256 _borrowAmtNeededToSwap = _borrowNeeded;
    if (_userProvidedDebtAmtMax > 0) {
      uint256 _borrowAmtFromUser = _userProvidedDebtAmtMax >= _borrowNeeded
        ? _borrowNeeded
        : _userProvidedDebtAmtMax;
      _borrowAmtNeededToSwap -= _borrowAmtFromUser;
      IERC20(_borrowToken).safeTransferFrom(
        _user,
        address(this),
        _borrowAmtFromUser
      );
    }
    if (_borrowAmtNeededToSwap > 0) {
      // sell pod token into LP for enough borrow token to get enough to repay
      _podAmtRemaining = _swapPodForBorrowToken(
        IDexAdapter(_dexAdapter),
        _pod,
        _borrowToken,
        _podAmtReceived,
        _borrowAmtNeededToSwap
      );
    }
  }

  function _swapPodForBorrowToken(
    IDexAdapter _dexAdapter,
    address _sourceToken,
    address _targetToken,
    uint256 _sourceAmt,
    uint256 _targetNeededAmt
  ) internal returns (uint256 _podRemainingAmt) {
    uint256 _balBefore = IERC20(_sourceToken).balanceOf(address(this));
    IERC20(_sourceToken).safeIncreaseAllowance(
      address(_dexAdapter),
      _sourceAmt
    );
    _dexAdapter.swapV2SingleExactOut(
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
    address _spTKN,
    IFlashLoanSource.FlashData memory _d,
    LeverageFlashProps memory _props
  )
    internal
    returns (uint256 _newAspTkns, uint256 _podAmountUsed, uint256 _pairedLpUsed)
  {
    uint256 _podBalBefore = IERC20(_props.pod).balanceOf(address(this));
    uint256 _pairedLpBalBefore = IERC20(_d.token).balanceOf(address(this));
    uint256 _stakeBalBefore = IERC20(_spTKN).balanceOf(address(this));
    IERC20(_props.pod).safeIncreaseAllowance(
      address(indexUtils),
      _props.podAmount
    );
    IERC20(_d.token).safeIncreaseAllowance(address(indexUtils), _d.amount);
    indexUtils.addLPAndStake(
      IDecentralizedIndex(_props.pod),
      _props.podAmount,
      _d.token,
      _d.amount, // == _props.pairedLpDesired
      _props.pairedLpAmtMin,
      _props.slippage,
      _props.deadline
    );
    uint256 _newStakes = IERC20(_spTKN).balanceOf(address(this)) -
      _stakeBalBefore;
    IERC20(_spTKN).safeIncreaseAllowance(aspTkn[_props.pod], _newStakes);

    _newAspTkns = IERC4626(aspTkn[_props.pod]).deposit(
      _newStakes,
      address(this)
    );
    _podAmountUsed =
      _podBalBefore -
      IERC20(_props.pod).balanceOf(address(this));
    _pairedLpUsed =
      _pairedLpBalBefore -
      IERC20(_d.token).balanceOf(address(this));
  }

  function _unstakeAndRemoveLP(
    address _pod,
    uint256 _collateralAssetAmtRemove,
    uint256 _podAmtMin,
    uint256 _pairedAssetAmtMin
  ) internal returns (uint256 _podAmtReceived, uint256 _borrowAmtReceived) {
    address _spTKN = IDecentralizedIndex(_pod).lpStakingPool();
    address _pairedLpToken = IDecentralizedIndex(_pod).PAIRED_LP_TOKEN();

    uint256 _podAmtBefore = IERC20(_pod).balanceOf(address(this));
    uint256 _pairedTokenAmtBefore = IERC20(_pairedLpToken).balanceOf(
      address(this)
    );

    uint256 _spTKNAmtReceived = IERC4626(aspTkn[_pod]).redeem(
      _collateralAssetAmtRemove,
      address(this),
      address(this)
    );
    IERC20(_spTKN).safeIncreaseAllowance(
      address(indexUtils),
      _spTKNAmtReceived
    );
    indexUtils.unstakeAndRemoveLP(
      IDecentralizedIndex(_pod),
      _spTKNAmtReceived,
      _podAmtMin,
      _pairedAssetAmtMin,
      block.timestamp
    );
    _podAmtReceived = IERC20(_pod).balanceOf(address(this)) - _podAmtBefore;
    _borrowAmtReceived =
      IERC20(_pairedLpToken).balanceOf(address(this)) -
      _pairedTokenAmtBefore;
  }

  function setIndexUtils(IIndexUtils_LEGACY _utils) external onlyOwner {
    indexUtils = _utils;
  }

  function rescueETH() external onlyOwner {
    (bool _s, ) = payable(_msgSender()).call{ value: address(this).balance }(
      ''
    );
    require(_s, 'S');
  }

  function rescueTokens(IERC20 _token) external onlyOwner {
    _token.safeTransfer(_msgSender(), _token.balanceOf(address(this)));
  }

  receive() external payable {}
}

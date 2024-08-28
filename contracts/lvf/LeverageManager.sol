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

  uint16 public openFeePerc; // 1000 precision
  uint16 public closeFeePerc; // 1000 precision

  // positionId => position props
  mapping(uint256 => LeveragePositionProps) public positionProps;

  event AddLeverage(uint256 indexed positionId, address indexed user);

  modifier onlyPositionOwner(uint256 _positionId) {
    require(positionNFT.ownerOf(_positionId) == _msgSender(), 'AUTH');
    _;
  }

  bool _initialised;
  modifier workflow(bool _starting) {
    if (_starting) {
      require(!_initialised, 'W0');
      _initialised = true;
    } else {
      require(_initialised, 'W1');
      _initialised = false;
    }
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

  /// @notice The ```initializePosition``` function initializes a new position and mints a new position NFT
  /// @param _pod The pod to leverage against for the new position
  /// @param _recipient User to receive the position NFT
  /// @param _selfLendingPod Optional self lending pod, use address(0) if not applicable
  function initializePosition(
    address _pod,
    address _recipient,
    address _selfLendingPod
  ) external override {
    _initializePosition(_pod, _recipient, _selfLendingPod);
  }

  /// @notice The ```addLeverage``` function adds leverage to a position (or creates a new one and adds leverage)
  /// @param _positionId The NFT ID of an existing position to add leverage to, or 0 if a new position should be created
  /// @param _pod The pod to leverage against for the position
  /// @param _podAmount Amount of pTKN to use to leverage against
  /// @param _pairedLpDesired Number of pairedLpTkn for the pod to use to add LP for the new position
  /// @param _pairedLpAmtMin Minimum number of pairedLpTkn for LP, slippage
  /// @param _slippage Slippage for the LP execution with 1000 precision (1000 == 100%)
  /// @param _deadline LP deadline for the UniswapV2 implementation
  /// @param _selfLendingPairPod Advanced implementation parameter that is a pod to wrap pairedLpTkn into before adding leverage, or address(0) if not applicable
  function addLeverage(
    uint256 _positionId,
    address _pod,
    uint256 _podAmount,
    uint256 _pairedLpDesired,
    uint256 _pairedLpAmtMin,
    uint256 _slippage,
    uint256 _deadline,
    address _selfLendingPairPod
  ) external override workflow(true) {
    if (_positionId == 0) {
      _positionId = _initializePosition(
        _pod,
        _msgSender(),
        _selfLendingPairPod
      );
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

    IERC20(_pod).safeTransferFrom(_msgSender(), address(this), _podAmount);

    // if additional fees required for flash source, handle that here
    _processExtraFlashLoanPayment(_pod, _msgSender());

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
        deadline: _deadline,
        selfLendingPairPod: _selfLendingPairPod
      }),
      _noop
    );
    IFlashLoanSource(flashSource[_pod]).flash(
      _getBorrowTknForPod(_pod),
      _pairedLpDesired,
      address(this),
      _leverageData
    );
  }

  /// @notice The ```removeLeverage``` function removes leverage from a position
  /// @param _positionId The NFT ID for the position
  /// @param _borrowAssetAmt Amount of borrowed assets to flash loan and use pay back and remove leverage
  /// @param _collateralAssetRemoveAmt Amount of collateral asset to remvoe from the position
  /// @param _podAmtMin Minimum amount of pTKN to receive on remove LP transaction (slippage)
  /// @param _pairedAssetAmtMin Minimum amount of pairedLpTkn to receive on remove LP transaction (slippage)
  /// @param _dexAdapter Adapter to use to optionally swap pod token into borrow token if not received enough to pay back flash loan
  /// @param _userProvidedDebtAmtMax Amt of borrow token a user will allow to transfer from their wallet to pay back flash loan
  function removeLeverage(
    uint256 _positionId,
    uint256 _borrowAssetAmt,
    uint256 _collateralAssetRemoveAmt,
    uint256 _podAmtMin,
    uint256 _pairedAssetAmtMin,
    address _dexAdapter,
    uint256 _userProvidedDebtAmtMax
  ) external override onlyPositionOwner(_positionId) workflow(true) {
    LeveragePositionProps memory _props = positionProps[_positionId];

    // if additional fees required for flash source, handle that here
    _processExtraFlashLoanPayment(_props.pod, _msgSender());

    address _borrowTkn = _getBorrowTknForPod(_props.pod);
    uint256 _borrowSharesToRepay = IFraxlendPair(lendingPairs[_props.pod])
      .totalBorrow()
      .toShares(_borrowAssetAmt, true);

    // needed to repay flash loaned asset in lending pair
    // before removing collateral and unwinding
    IERC20(_borrowTkn).safeIncreaseAllowance(
      lendingPairs[_props.pod],
      _borrowAssetAmt
    );

    LeverageFlashProps memory _position;
    _position.method = FlashCallbackMethod.REMOVE;
    _position.positionId = _positionId;
    _position.user = _msgSender();
    _position.pod = _props.pod;
    bytes memory _additionalInfo = abi.encode(
      _borrowSharesToRepay,
      _collateralAssetRemoveAmt,
      _podAmtMin,
      _pairedAssetAmtMin,
      _dexAdapter,
      _userProvidedDebtAmtMax
    );
    IFlashLoanSource(flashSource[_props.pod]).flash(
      _borrowTkn,
      _borrowAssetAmt,
      address(this),
      abi.encode(_position, _additionalInfo)
    );
  }

  /// @notice The ```withdrawAssets``` function allows a position owner to withdraw any assets in the position custodian
  /// @param _positionId The NFT ID for the position
  /// @param _token The token to withdraw assets from
  /// @param _recipient Where the received assets should go
  /// @param _amount How much to withdraw
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

  /// @notice The ```callback``` function can only be called within the addLeverage or removeLeverage workflow,
  /// @notice and is called by the flash source implementation used to borrow assets to initiate adding or removing lev
  /// @param _userData Config/info to unpack and extract individual pieces when adding/removing leverage, see addLeverage and removeLeverage
  function callback(bytes memory _userData) external override workflow(false) {
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
        // if there's a close fee send returned pod tokens for fee to protocol
        if (closeFeePerc > 0) {
          uint256 _closeFeeAmt = (_podAmtToUser * closeFeePerc) / 1000;
          IERC20(_posProps.pod).safeTransfer(owner(), _closeFeeAmt);
          _podAmtToUser -= _closeFeeAmt;
        }
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
    address _recipient,
    address _selfLendingPod
  ) internal returns (uint256 _positionId) {
    require(lendingPairs[_pod] != address(0), 'LVP');
    _positionId = positionNFT.mint(_recipient);
    LeveragePositionCustodian _custodian = new LeveragePositionCustodian();
    positionProps[_positionId] = LeveragePositionProps({
      pod: _pod,
      lendingPair: lendingPairs[_pod],
      custodian: address(_custodian),
      selfLendingPod: _selfLendingPod
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

    // if there's an open fee send aspTKN generated to protocol
    address _aspTkn = _getAspTkn(_props.pod);
    if (openFeePerc > 0) {
      uint256 _openFeeAmt = (_aspTknCollateralBal * openFeePerc) / 1000;
      IERC20(_aspTkn).safeTransfer(owner(), _openFeeAmt);
      _aspTknCollateralBal -= _openFeeAmt;
    }

    IERC20(_aspTkn).safeTransfer(
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
      uint256 _collateralAssetRemoveAmt,
      uint256 _podAmtMin,
      uint256 _pairedAssetAmtMin,
      address _dexAdapter,
      uint256 _userProvidedDebtAmtMax
    ) = abi.decode(
        _additionalInfo,
        (uint256, uint256, uint256, uint256, address, uint256)
      );

    address _lendingPair = lendingPairs[_props.pod];

    // allowance increases for _borrowAssetAmt prior to flash loaning asset
    IFraxlendPair(_lendingPair).repayAsset(
      _borrowSharesToRepay,
      positionProps[_props.positionId].custodian
    );
    LeveragePositionCustodian(positionProps[_props.positionId].custodian)
      .removeCollateral(_lendingPair, _collateralAssetRemoveAmt, address(this));
    (uint256 _podAmtReceived, uint256 _pairedAmtReceived) = _unstakeAndRemoveLP(
      _props.pod,
      _collateralAssetRemoveAmt,
      _podAmtMin,
      _pairedAssetAmtMin
    );
    _podAmtRemaining = _podAmtReceived;

    // redeem borrow asset from lending pair for self lending positions
    if (_isSelfLendingAndOrPodded(_props.pod)) {
      // unwrap from self lending pod for lending pair asset
      if (positionProps[_props.positionId].selfLendingPod != address(0)) {
        _pairedAmtReceived = _debondFromSelfLendingPod(
          positionProps[_props.positionId].selfLendingPod,
          _pairedAmtReceived
        );
      }

      IFraxlendPair(_lendingPair).redeem(
        _pairedAmtReceived,
        address(this),
        address(this)
      );
      _pairedAmtReceived = IERC20(_d.token).balanceOf(address(this));
    }

    // pay back flash loan and send remaining to borrower
    uint256 _repayAmount = _d.amount + _d.fee;
    if (_pairedAmtReceived < _repayAmount) {
      _podAmtRemaining = _acquireBorrowTokenForRepayment(
        _props.pod,
        _props.user,
        _d.token,
        _dexAdapter,
        _repayAmount,
        _pairedAmtReceived,
        _podAmtReceived,
        _userProvidedDebtAmtMax
      );
    }
    IERC20(_d.token).safeTransfer(
      IFlashLoanSource(flashSource[_props.pod]).source(),
      _repayAmount
    );
    _borrowAmtRemaining = _pairedAmtReceived > _repayAmount
      ? _pairedAmtReceived - _repayAmount
      : 0;
  }

  function _debondFromSelfLendingPod(
    address _pod,
    uint256 _amount
  ) internal returns (uint256 _amtOut) {
    IDecentralizedIndex.IndexAssetInfo[]
      memory _podAssets = IDecentralizedIndex(_pod).getAllAssets();
    address[] memory _tokens = new address[](1);
    uint8[] memory _percentages = new uint8[](1);
    _tokens[0] = _podAssets[0].token;
    _percentages[0] = 100;
    IDecentralizedIndex(_pod).debond(_amount, _tokens, _percentages);
    _amtOut = IERC20(_tokens[0]).balanceOf(address(this));
  }

  function _acquireBorrowTokenForRepayment(
    address _pod,
    address _user,
    address _borrowToken,
    address _dexAdapter,
    uint256 _repayAmount,
    uint256 _pairedAmtReceived,
    uint256 _podAmtReceived,
    uint256 _userProvidedDebtAmtMax
  ) internal returns (uint256 _podAmtRemaining) {
    _podAmtRemaining = _podAmtReceived;
    uint256 _borrowNeeded = _repayAmount - _pairedAmtReceived;
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
    (address _pairedLpForPod, uint256 _pairedLpAmt) = _getPairedTknAndAmt(
      _props.pod,
      _d.token,
      _d.amount,
      _props.selfLendingPairPod
    );
    uint256 _podBalBefore = IERC20(_props.pod).balanceOf(address(this));
    uint256 _pairedLpBalBefore = IERC20(_pairedLpForPod).balanceOf(
      address(this)
    );
    IERC20(_props.pod).safeIncreaseAllowance(
      address(indexUtils),
      _props.podAmount
    );
    IERC20(_pairedLpForPod).safeIncreaseAllowance(
      address(indexUtils),
      _pairedLpAmt
    );
    indexUtils.addLPAndStake(
      IDecentralizedIndex(_props.pod),
      _props.podAmount,
      _pairedLpForPod,
      _pairedLpAmt,
      _props.pairedLpAmtMin,
      _props.slippage,
      _props.deadline
    );

    address _aspTkn = _getAspTkn(_props.pod);
    uint256 _stakingBal = IERC20(_spTKN).balanceOf(address(this));
    IERC20(_spTKN).safeIncreaseAllowance(_aspTkn, _stakingBal);
    _newAspTkns = IERC4626(_aspTkn).deposit(_stakingBal, address(this));
    _podAmountUsed =
      _podBalBefore -
      IERC20(_props.pod).balanceOf(address(this));
    _pairedLpUsed =
      _pairedLpBalBefore -
      IERC20(_pairedLpForPod).balanceOf(address(this));

    // for self lending pods redeem any extra paired LP asset back into main asset
    uint256 _pairedLeftover = _pairedLpBalBefore - _pairedLpUsed;
    if (_isSelfLendingAndOrPodded(_props.pod) && _pairedLeftover > 0) {
      if (_props.selfLendingPairPod != address(0)) {
        address[] memory _noop1 = new address[](0);
        uint8[] memory _noop2 = new uint8[](0);
        IDecentralizedIndex(_props.selfLendingPairPod).debond(
          _pairedLeftover,
          _noop1,
          _noop2
        );
        _pairedLeftover = IERC20(lendingPairs[_props.pod]).balanceOf(
          address(this)
        );
      }
      IFraxlendPair(lendingPairs[_props.pod]).redeem(
        _pairedLeftover,
        address(this),
        address(this)
      );
    }
  }

  function _getPairedTknAndAmt(
    address _pod,
    address _borrowedTkn,
    uint256 _borrowedAmt,
    address _selfLendingPairPod
  ) internal returns (address _finalPairedTkn, uint256 _finalPairedAmt) {
    _finalPairedTkn = _borrowedTkn;
    _finalPairedAmt = _borrowedAmt;
    if (_isSelfLendingAndOrPodded(_pod)) {
      _finalPairedTkn = lendingPairs[_pod];
      IERC20(_borrowedTkn).safeIncreaseAllowance(
        lendingPairs[_pod],
        _finalPairedAmt
      );
      _finalPairedAmt = IFraxlendPair(lendingPairs[_pod]).deposit(
        _finalPairedAmt,
        address(this)
      );

      // self lending+podded
      if (_selfLendingPairPod != address(0)) {
        _finalPairedTkn = _selfLendingPairPod;
        IERC20(lendingPairs[_pod]).safeIncreaseAllowance(
          _selfLendingPairPod,
          _finalPairedAmt
        );
        IDecentralizedIndex(_selfLendingPairPod).bond(
          lendingPairs[_pod],
          _finalPairedAmt,
          0
        );
        _finalPairedAmt = IERC20(_selfLendingPairPod).balanceOf(address(this));
      }
    }
  }

  function _unstakeAndRemoveLP(
    address _pod,
    uint256 _collateralAssetRemoveAmt,
    uint256 _podAmtMin,
    uint256 _pairedAssetAmtMin
  ) internal returns (uint256 _podAmtReceived, uint256 _pairedAmtReceived) {
    address _spTKN = IDecentralizedIndex(_pod).lpStakingPool();
    address _pairedLpToken = IDecentralizedIndex(_pod).PAIRED_LP_TOKEN();

    uint256 _podAmtBefore = IERC20(_pod).balanceOf(address(this));
    uint256 _pairedTokenAmtBefore = IERC20(_pairedLpToken).balanceOf(
      address(this)
    );

    uint256 _spTKNAmtReceived = IERC4626(_getAspTkn(_pod)).redeem(
      _collateralAssetRemoveAmt,
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
    _pairedAmtReceived =
      IERC20(_pairedLpToken).balanceOf(address(this)) -
      _pairedTokenAmtBefore;
  }

  function _isSelfLendingAndOrPodded(
    address _pod
  ) internal view returns (bool) {
    return
      IDecentralizedIndex(_pod).PAIRED_LP_TOKEN() !=
      IFraxlendPair(lendingPairs[_pod]).asset();
  }

  function _getBorrowTknForPod(address _pod) internal view returns (address) {
    return
      _isSelfLendingAndOrPodded(_pod)
        ? IFraxlendPair(lendingPairs[_pod]).asset()
        : IDecentralizedIndex(_pod).PAIRED_LP_TOKEN();
  }

  function _getAspTkn(address _pod) internal view returns (address) {
    return IFraxlendPair(lendingPairs[_pod]).collateralContract();
  }

  function setIndexUtils(IIndexUtils_LEGACY _utils) external onlyOwner {
    indexUtils = _utils;
  }

  function setOpenFeePerc(uint16 _newFee) external onlyOwner {
    require(_newFee <= 250, 'MAX');
    openFeePerc = _newFee;
  }

  function setCloseFeePerc(uint16 _newFee) external onlyOwner {
    require(_newFee <= 250, 'MAX');
    closeFeePerc = _newFee;
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

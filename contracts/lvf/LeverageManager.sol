// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "../interfaces/IDecentralizedIndex.sol";
import "../interfaces/IDexAdapter.sol";
import "../interfaces/IFlashLoanRecipient.sol";
import "../interfaces/IIndexUtils.sol";
import "../interfaces/ILeverageManager.sol";
import {VaultAccount, VaultAccountingLibrary} from "../libraries/VaultAccount.sol";
import "./LeverageManagerAccessControl.sol";
import "./LeveragePositions.sol";
import "./LeveragePositionCustodian.sol";

contract LeverageManager is ILeverageManager, IFlashLoanRecipient, Context, LeverageManagerAccessControl {
    using SafeERC20 for IERC20;
    using VaultAccountingLibrary for VaultAccount;

    IIndexUtils public indexUtils;
    LeveragePositions public positionNFT;

    address public feeReceiver;
    uint16 public openFeePerc; // 1000 precision
    uint16 public closeFeePerc; // 1000 precision

    // positionId => position props
    mapping(uint256 => LeveragePositionProps) public positionProps;

    modifier onlyPositionOwner(uint256 _positionId) {
        require(positionNFT.ownerOf(_positionId) == _msgSender(), "A0");
        _;
    }

    bool _initialised;

    modifier workflow(bool _starting) {
        if (_starting) {
            require(!_initialised, "W0");
            _initialised = true;
        } else {
            require(_initialised, "W1");
            _initialised = false;
        }
        _;
    }

    constructor(string memory _positionName, string memory _positionSymbol, IIndexUtils _idxUtils) {
        feeReceiver = _msgSender();
        indexUtils = _idxUtils;
        positionNFT = new LeveragePositions(_positionName, _positionSymbol);
    }

    /// @notice The ```initializePosition``` function initializes a new position and mints a new position NFT
    /// @param _pod The pod to leverage against for the new position
    /// @param _recipient User to receive the position NFT
    /// @param _overrideLendingPair If it's a self-lending pod, an override lending pair the user will use
    /// @param _hasSelfLendingPairPod bool Advanced implementation parameter that determines whether or not the self lending pod's paired LP asset (fTKN) is podded as well
    function initializePosition(
        address _pod,
        address _recipient,
        address _overrideLendingPair,
        bool _hasSelfLendingPairPod
    ) external override returns (uint256 _positionId) {
        _positionId = _initializePosition(_pod, _recipient, _overrideLendingPair, _hasSelfLendingPairPod);
    }

    /// @notice The ```addLeverage``` function adds leverage to a position (or creates a new one and adds leverage)
    /// @param _positionId The NFT ID of an existing position to add leverage to, or 0 if a new position should be created
    /// @param _pod The pod to leverage against for the position
    /// @param _pTknAmt Amount of pTKN to use to leverage against
    /// @param _pairedLpDesired Total amount of pairedLpTkn for the pod to use to add LP for the new position (including _userProvidedDebtAmt)
    /// @param _userProvidedDebtAmt Amt of borrow token a user will provide to reduce flash loan amount and ultimately borrowed position LTV
    /// @param _hasSelfLendingPairPod bool Advanced implementation parameter that determines whether or not the self lending pod's paired LP asset (fTKN) is podded as well
    /// @param _config Extra config to apply when leveraging a position abi.encode(uint256,uint256,uint256)
    /// @dev _config[0] == overrideBorrowAmt Override amount to borrow from the lending pair, only matters if max LTV is >50% on the lending pair
    /// @dev _config[1] == slippage for the LP execution with 1000 precision (1000 == 100%)
    /// @dev _config[2] == deadline LP deadline for the UniswapV2 implementation
    function addLeverage(
        uint256 _positionId,
        address _pod,
        uint256 _pTknAmt,
        uint256 _pairedLpDesired,
        uint256 _userProvidedDebtAmt,
        bool _hasSelfLendingPairPod,
        bytes memory _config
    ) external override workflow(true) {
        uint256 _pTknBalBefore = IERC20(_pod).balanceOf(address(this));
        IERC20(_pod).safeTransferFrom(_msgSender(), address(this), _pTknAmt);
        _addLeveragePreCallback(
            _msgSender(),
            _positionId,
            _pod,
            IERC20(_pod).balanceOf(address(this)) - _pTknBalBefore,
            _pairedLpDesired,
            _userProvidedDebtAmt,
            _hasSelfLendingPairPod,
            _config
        );
    }

    /// @notice The ```addLeverageFromTkn``` function adds leverage to a position (or creates a new one and adds leverage) using underlying pod's TKN
    /// @param _positionId The NFT ID of an existing position to add leverage to, or 0 if a new position should be created
    /// @param _pod The pod to leverage against for the position
    /// @param _tknAmt Amount of underlying pod TKN to use to leverage against
    /// @param _amtPtknMintMin Amount of minimum pTKN that should be minted from provided underlying TKN
    /// @param _pairedLpDesired Total amount of pairedLpTkn for the pod to use to add LP for the new position (including _userProvidedDebtAmt)
    /// @param _userProvidedDebtAmt Amt of borrow token a user will provide to reduce flash loan amount and ultimately borrowed position LTV
    /// @param _hasSelfLendingPairPod bool Advanced implementation parameter that determines whether or not the self lending pod's paired LP asset (fTKN) is podded as well
    /// @param _config Extra config to apply when leveraging a position abi.encode(uint256,uint256,uint256)
    /// @dev _config[0] == overrideBorrowAmt Override amount to borrow from the lending pair, only matters if max LTV is >50% on the lending pair
    /// @dev _config[1] == slippage for the LP execution with 1000 precision (1000 == 100%)
    /// @dev _config[2] == deadline LP deadline for the UniswapV2 implementation
    function addLeverageFromTkn(
        uint256 _positionId,
        address _pod,
        uint256 _tknAmt,
        uint256 _amtPtknMintMin,
        uint256 _pairedLpDesired,
        uint256 _userProvidedDebtAmt,
        bool _hasSelfLendingPairPod,
        bytes memory _config
    ) external override workflow(true) {
        uint256 _pTknBalBefore = IERC20(_pod).balanceOf(address(this));
        _bondToPod(_msgSender(), _pod, _tknAmt, _amtPtknMintMin);
        _addLeveragePreCallback(
            _msgSender(),
            _positionId,
            _pod,
            IERC20(_pod).balanceOf(address(this)) - _pTknBalBefore,
            _pairedLpDesired,
            _userProvidedDebtAmt,
            _hasSelfLendingPairPod,
            _config
        );
    }

    /// @notice The ```removeLeverage``` function removes leverage from a position
    /// @param _positionId The NFT ID for the position
    /// @param _borrowAssetAmt Amount of borrowed assets to flash loan and use pay back and remove leverage
    /// @param _collateralAssetRemoveAmt Amount of collateral asset to remove from the position
    /// @param _podAmtMin Minimum amount of pTKN to receive on remove LP transaction (slippage)
    /// @param _pairedAssetAmtMin Minimum amount of pairedLpTkn to receive on remove LP transaction (slippage)
    /// @param _podSwapAmtOutMin Minimum amount of pTKN to receive if it's required to swap pTKN for pairedLpTkn in order to pay back the flash loan
    /// @param _userProvidedDebtAmtMax Amt of borrow token a user will allow to transfer from their wallet to pay back flash loan
    function removeLeverage(
        uint256 _positionId,
        uint256 _borrowAssetAmt,
        uint256 _collateralAssetRemoveAmt,
        uint256 _podAmtMin,
        uint256 _pairedAssetAmtMin,
        uint256 _podSwapAmtOutMin,
        uint256 _userProvidedDebtAmtMax
    ) external override workflow(true) {
        address _sender = _msgSender();
        address _owner = positionNFT.ownerOf(_positionId);
        require(
            _owner == _sender || positionNFT.getApproved(_positionId) == _sender
                || positionNFT.isApprovedForAll(_owner, _sender),
            "A1"
        );

        address _lendingPair = positionProps[_positionId].lendingPair;
        IFraxlendPair(_lendingPair).addInterest(false);

        // if additional fees required for flash source, handle that here
        _processExtraFlashLoanPayment(_positionId, _sender);

        address _borrowTkn = _getBorrowTknForPod(_positionId);

        // needed to repay flash loaned asset in lending pair
        // before removing collateral and unwinding
        IERC20(_borrowTkn).safeIncreaseAllowance(_lendingPair, _borrowAssetAmt);

        LeverageFlashProps memory _props;
        _props.method = FlashCallbackMethod.REMOVE;
        _props.positionId = _positionId;
        _props.owner = _owner;
        bytes memory _additionalInfo = abi.encode(
            IFraxlendPair(_lendingPair).totalBorrow().toShares(_borrowAssetAmt, false),
            _collateralAssetRemoveAmt,
            _podAmtMin,
            _pairedAssetAmtMin,
            _podSwapAmtOutMin,
            _userProvidedDebtAmtMax
        );
        IFlashLoanSource(_getFlashSource(_positionId)).flash(
            _borrowTkn, _borrowAssetAmt, address(this), abi.encode(_props, _additionalInfo)
        );
    }

    /// @notice The ```withdrawAssets``` function allows a position owner to withdraw any assets in the position custodian
    /// @param _positionId The NFT ID for the position
    /// @param _token The token to withdraw assets from
    /// @param _recipient Where the received assets should go
    /// @param _amount How much to withdraw
    function withdrawAssets(uint256 _positionId, address _token, address _recipient, uint256 _amount)
        external
        onlyPositionOwner(_positionId)
    {
        LeveragePositionCustodian(positionProps[_positionId].custodian).withdraw(_token, _recipient, _amount);
    }

    /// @notice The ```callback``` function can only be called within the addLeverage or removeLeverage workflow,
    /// @notice and is called by the flash source implementation used to borrow assets to initiate adding or removing lev
    /// @param _userData Config/info to unpack and extract individual pieces when adding/removing leverage, see addLeverage and removeLeverage
    function callback(bytes memory _userData) external override workflow(false) {
        IFlashLoanSource.FlashData memory _d = abi.decode(_userData, (IFlashLoanSource.FlashData));
        (LeverageFlashProps memory _posProps,) = abi.decode(_d.data, (LeverageFlashProps, bytes));

        address _pod = positionProps[_posProps.positionId].pod;

        require(_getFlashSource(_posProps.positionId) == _msgSender(), "A2");

        if (_posProps.method == FlashCallbackMethod.ADD) {
            uint256 _ptknRefundAmt = _addLeveragePostCallback(_userData);
            if (_ptknRefundAmt > 0) {
                IERC20(_pod).safeTransfer(_posProps.owner, _ptknRefundAmt);
            }
        } else if (_posProps.method == FlashCallbackMethod.REMOVE) {
            (uint256 _ptknToUserAmt, uint256 _pairedLpToUser) = _removeLeveragePostCallback(_userData);
            if (_ptknToUserAmt > 0) {
                // if there's a close fee send returned pod tokens for fee to protocol
                if (closeFeePerc > 0) {
                    uint256 _closeFeeAmt = (_ptknToUserAmt * closeFeePerc) / 1000;
                    IERC20(_pod).safeTransfer(feeReceiver, _closeFeeAmt);
                    _ptknToUserAmt -= _closeFeeAmt;
                }
                IERC20(_pod).safeTransfer(_posProps.owner, _ptknToUserAmt);
            }
            if (_pairedLpToUser > 0) {
                IERC20(_getBorrowTknForPod(_posProps.positionId)).safeTransfer(_posProps.owner, _pairedLpToUser);
            }
        } else {
            require(false, "NI");
        }
    }

    function _initializePosition(
        address _pod,
        address _recipient,
        address _overrideLendingPair,
        bool _hasSelfLendingPairPod
    ) internal returns (uint256 _positionId) {
        if (lendingPairs[_pod] == address(0)) {
            require(_overrideLendingPair != address(0), "OLP");
        }
        _positionId = positionNFT.mint(_recipient);
        LeveragePositionCustodian _custodian = new LeveragePositionCustodian();
        positionProps[_positionId] = LeveragePositionProps({
            pod: _pod,
            lendingPair: lendingPairs[_pod] == address(0) ? _overrideLendingPair : lendingPairs[_pod],
            custodian: address(_custodian),
            isSelfLending: lendingPairs[_pod] == address(0) && _overrideLendingPair != address(0),
            hasSelfLendingPairPod: _hasSelfLendingPairPod
        });
    }

    function _processExtraFlashLoanPayment(uint256 _positionId, address _user) internal {
        address _posFlashSrc = _getFlashSource(_positionId);
        IFlashLoanSource _flashLoanSource = IFlashLoanSource(_posFlashSrc);
        uint256 _flashPaymentAmount = _flashLoanSource.paymentAmount();
        if (_flashPaymentAmount > 0) {
            address _paymentAsset = _flashLoanSource.paymentToken();
            IERC20(_paymentAsset).safeTransferFrom(_user, address(this), _flashPaymentAmount);
            IERC20(_paymentAsset).safeIncreaseAllowance(_posFlashSrc, _flashPaymentAmount);
        }
    }

    function _addLeveragePreCallback(
        address _sender,
        uint256 _positionId,
        address _pod,
        uint256 _pTknAmt,
        uint256 _pairedLpDesired,
        uint256 _userProvidedDebtAmt,
        bool _hasSelfLendingPairPod,
        bytes memory _config
    ) internal {
        if (_positionId == 0) {
            _positionId = _initializePosition(_pod, _sender, address(0), _hasSelfLendingPairPod);
        } else {
            address _owner = positionNFT.ownerOf(_positionId);
            require(
                _owner == _sender || positionNFT.getApproved(_positionId) == _sender
                    || positionNFT.isApprovedForAll(_owner, _sender),
                "A3"
            );
            _pod = positionProps[_positionId].pod;
        }
        require(_getFlashSource(_positionId) != address(0), "FSV");

        if (_userProvidedDebtAmt > 0) {
            IERC20(_getBorrowTknForPod(_positionId)).safeTransferFrom(_sender, address(this), _userProvidedDebtAmt);
        }

        // if additional fees required for flash source, handle that here
        _processExtraFlashLoanPayment(_positionId, _sender);

        IFlashLoanSource(_getFlashSource(_positionId)).flash(
            _getBorrowTknForPod(_positionId),
            _pairedLpDesired - _userProvidedDebtAmt,
            address(this),
            _getFlashDataAddLeverage(_positionId, _sender, _pTknAmt, _pairedLpDesired, _config)
        );
    }

    function _addLeveragePostCallback(bytes memory _data) internal returns (uint256 _ptknRefundAmt) {
        IFlashLoanSource.FlashData memory _d = abi.decode(_data, (IFlashLoanSource.FlashData));
        (LeverageFlashProps memory _props,) = abi.decode(_d.data, (LeverageFlashProps, bytes));
        (uint256 _overrideBorrowAmt,,) = abi.decode(_props.config, (uint256, uint256, uint256));
        address _pod = positionProps[_props.positionId].pod;
        uint256 _borrowTknAmtToLp = _props.pairedLpDesired;
        // if there's an open fee send debt/borrow token to protocol
        if (openFeePerc > 0) {
            uint256 _openFeeAmt = (_borrowTknAmtToLp * openFeePerc) / 1000;
            IERC20(_d.token).safeTransfer(feeReceiver, _openFeeAmt);
            _borrowTknAmtToLp -= _openFeeAmt;
        }
        (uint256 _pTknAmtUsed,, uint256 _pairedLeftover) = _lpAndStakeInPod(_d.token, _borrowTknAmtToLp, _props);
        _ptknRefundAmt = _props.pTknAmt - _pTknAmtUsed;

        uint256 _aspTknCollateralBal =
            _spTknToAspTkn(IDecentralizedIndex(_pod).lpStakingPool(), _pairedLeftover, _props);

        uint256 _flashPaybackAmt = _d.amount + _d.fee;
        uint256 _borrowAmt = _overrideBorrowAmt > _flashPaybackAmt ? _overrideBorrowAmt : _flashPaybackAmt;

        address _aspTkn = _getAspTkn(_props.positionId);
        IERC20(_aspTkn).safeTransfer(positionProps[_props.positionId].custodian, _aspTknCollateralBal);
        LeveragePositionCustodian(positionProps[_props.positionId].custodian).borrowAsset(
            positionProps[_props.positionId].lendingPair, _borrowAmt, _aspTknCollateralBal, address(this)
        );

        // pay back flash loan and send remaining to borrower
        IERC20(_d.token).safeTransfer(IFlashLoanSource(_getFlashSource(_props.positionId)).source(), _flashPaybackAmt);
        uint256 _remaining = IERC20(_d.token).balanceOf(address(this));
        if (_remaining != 0) {
            IERC20(_d.token).safeTransfer(positionNFT.ownerOf(_props.positionId), _remaining);
        }
        emit AddLeverage(_props.positionId, _props.owner, _pTknAmtUsed, _aspTknCollateralBal, _borrowAmt);
    }

    function _removeLeveragePostCallback(bytes memory _userData)
        internal
        returns (uint256 _podAmtRemaining, uint256 _borrowAmtRemaining)
    {
        IFlashLoanSource.FlashData memory _d = abi.decode(_userData, (IFlashLoanSource.FlashData));
        (LeverageFlashProps memory _props, bytes memory _additionalInfo) =
            abi.decode(_d.data, (LeverageFlashProps, bytes));
        (
            uint256 _borrowSharesToRepay,
            uint256 _collateralAssetRemoveAmt,
            uint256 _podAmtMin,
            uint256 _pairedAssetAmtMin,
            uint256 _podSwapAmtOutMin,
            uint256 _userProvidedDebtAmtMax
        ) = abi.decode(_additionalInfo, (uint256, uint256, uint256, uint256, uint256, uint256));

        LeveragePositionProps memory _posProps = positionProps[_props.positionId];

        // allowance increases for _borrowAssetAmt prior to flash loaning asset
        IFraxlendPair(_posProps.lendingPair).repayAsset(_borrowSharesToRepay, _posProps.custodian);
        LeveragePositionCustodian(_posProps.custodian).removeCollateral(
            _posProps.lendingPair, _collateralAssetRemoveAmt, address(this)
        );
        (uint256 _podAmtReceived, uint256 _pairedAmtReceived) = _unstakeAndRemoveLP(
            _props.positionId, _posProps.pod, _collateralAssetRemoveAmt, _podAmtMin, _pairedAssetAmtMin
        );
        _podAmtRemaining = _podAmtReceived;

        // redeem borrow asset from lending pair for self lending positions
        if (_isPodSelfLending(_props.positionId)) {
            // unwrap from self lending pod for lending pair asset
            if (_posProps.hasSelfLendingPairPod) {
                _pairedAmtReceived =
                    _debondFromSelfLendingPod(IDecentralizedIndex(_posProps.pod).PAIRED_LP_TOKEN(), _pairedAmtReceived);
            }

            IFraxlendPair(_posProps.lendingPair).redeem(_pairedAmtReceived, address(this), address(this));
            _pairedAmtReceived = IERC20(_d.token).balanceOf(address(this));
        }

        // pay back flash loan and send remaining to borrower
        uint256 _repayAmount = _d.amount + _d.fee;
        if (_pairedAmtReceived < _repayAmount) {
            _podAmtRemaining = _acquireBorrowTokenForRepayment(
                _props,
                _posProps.pod,
                _d.token,
                _repayAmount - _pairedAmtReceived,
                _podAmtReceived,
                _podSwapAmtOutMin,
                _userProvidedDebtAmtMax
            );
        }
        IERC20(_d.token).safeTransfer(IFlashLoanSource(_getFlashSource(_props.positionId)).source(), _repayAmount);
        _borrowAmtRemaining = _pairedAmtReceived > _repayAmount ? _pairedAmtReceived - _repayAmount : 0;
        emit RemoveLeverage(_props.positionId, _props.owner, _collateralAssetRemoveAmt);
    }

    function _debondFromSelfLendingPod(address _pod, uint256 _amount) internal returns (uint256 _amtOut) {
        IDecentralizedIndex.IndexAssetInfo[] memory _podAssets = IDecentralizedIndex(_pod).getAllAssets();
        address[] memory _tokens = new address[](1);
        uint8[] memory _percentages = new uint8[](1);
        _tokens[0] = _podAssets[0].token;
        _percentages[0] = 100;
        IDecentralizedIndex(_pod).debond(_amount, _tokens, _percentages);
        _amtOut = IERC20(_tokens[0]).balanceOf(address(this));
    }

    function _acquireBorrowTokenForRepayment(
        LeverageFlashProps memory _props,
        address _pod,
        address _borrowToken,
        uint256 _borrowNeeded,
        uint256 _podAmtReceived,
        uint256 _podSwapAmtOutMin,
        uint256 _userProvidedDebtAmtMax
    ) internal returns (uint256 _podAmtRemaining) {
        _podAmtRemaining = _podAmtReceived;
        uint256 _borrowAmtNeededToSwap = _borrowNeeded;
        if (_userProvidedDebtAmtMax > 0) {
            uint256 _borrowAmtFromUser =
                _userProvidedDebtAmtMax >= _borrowNeeded ? _borrowNeeded : _userProvidedDebtAmtMax;
            _borrowAmtNeededToSwap -= _borrowAmtFromUser;
            IERC20(_borrowToken).safeTransferFrom(_props.sender, address(this), _borrowAmtFromUser);
        }
        // sell pod token into LP for enough borrow token to get enough to repay
        // if self-lending swap for lending pair then redeem for borrow token
        if (_borrowAmtNeededToSwap > 0) {
            if (_isPodSelfLending(_props.positionId)) {
                _podAmtRemaining = _swapPodForBorrowToken(
                    _pod,
                    positionProps[_props.positionId].lendingPair,
                    _podAmtReceived,
                    IFraxlendPair(positionProps[_props.positionId].lendingPair).convertToShares(_borrowAmtNeededToSwap),
                    _podSwapAmtOutMin
                );
                IFraxlendPair(positionProps[_props.positionId].lendingPair).redeem(
                    IERC20(positionProps[_props.positionId].lendingPair).balanceOf(address(this)),
                    address(this),
                    address(this)
                );
            } else {
                _podAmtRemaining = _swapPodForBorrowToken(
                    _pod, _borrowToken, _podAmtReceived, _borrowAmtNeededToSwap, _podSwapAmtOutMin
                );
            }
        }
    }

    function _swapPodForBorrowToken(
        address _pod,
        address _targetToken,
        uint256 _podAmt,
        uint256 _targetNeededAmt,
        uint256 _podSwapAmtOutMin
    ) internal returns (uint256 _podRemainingAmt) {
        IDexAdapter _dexAdapter = IDecentralizedIndex(_pod).DEX_HANDLER();
        uint256 _balBefore = IERC20(_pod).balanceOf(address(this));
        IERC20(_pod).safeIncreaseAllowance(address(_dexAdapter), _podAmt);
        _dexAdapter.swapV2SingleExactOut(
            _pod, _targetToken, _podAmt, _podSwapAmtOutMin == 0 ? _targetNeededAmt : _podSwapAmtOutMin, address(this)
        );
        _podRemainingAmt = _podAmt - (_balBefore - IERC20(_pod).balanceOf(address(this)));
    }

    function _lpAndStakeInPod(address _borrowToken, uint256 _borrowAmt, LeverageFlashProps memory _props)
        internal
        returns (uint256 _pTknAmtUsed, uint256 _pairedLpUsed, uint256 _pairedLpLeftover)
    {
        (, uint256 _slippage, uint256 _deadline) = abi.decode(_props.config, (uint256, uint256, uint256));
        (address _pairedLpForPod, uint256 _pairedLpAmt) = _processAndGetPairedTknAndAmt(
            _props.positionId, _borrowToken, _borrowAmt, positionProps[_props.positionId].hasSelfLendingPairPod
        );
        uint256 _podBalBefore = IERC20(positionProps[_props.positionId].pod).balanceOf(address(this));
        uint256 _pairedLpBalBefore = IERC20(_pairedLpForPod).balanceOf(address(this));
        IERC20(positionProps[_props.positionId].pod).safeIncreaseAllowance(address(indexUtils), _props.pTknAmt);
        IERC20(_pairedLpForPod).safeIncreaseAllowance(address(indexUtils), _pairedLpAmt);
        indexUtils.addLPAndStake(
            IDecentralizedIndex(positionProps[_props.positionId].pod),
            _props.pTknAmt,
            _pairedLpForPod,
            _pairedLpAmt,
            0, // is not used so can use max slippage
            _slippage,
            _deadline
        );
        _pTknAmtUsed = _podBalBefore - IERC20(positionProps[_props.positionId].pod).balanceOf(address(this));
        _pairedLpUsed = _pairedLpBalBefore - IERC20(_pairedLpForPod).balanceOf(address(this));
        _pairedLpLeftover = _pairedLpBalBefore - _pairedLpUsed;
    }

    function _spTknToAspTkn(address _spTKN, uint256 _pairedRemainingAmt, LeverageFlashProps memory _props)
        internal
        returns (uint256 _newAspTkns)
    {
        address _aspTkn = _getAspTkn(_props.positionId);
        uint256 _stakingBal = IERC20(_spTKN).balanceOf(address(this));
        IERC20(_spTKN).safeIncreaseAllowance(_aspTkn, _stakingBal);
        _newAspTkns = IERC4626(_aspTkn).deposit(_stakingBal, address(this));

        // for self lending pods redeem any extra paired LP asset back into main asset
        if (_isPodSelfLending(_props.positionId) && _pairedRemainingAmt > 0) {
            if (positionProps[_props.positionId].hasSelfLendingPairPod) {
                address[] memory _noop1;
                uint8[] memory _noop2;
                IDecentralizedIndex(IDecentralizedIndex(positionProps[_props.positionId].pod).PAIRED_LP_TOKEN()).debond(
                    _pairedRemainingAmt, _noop1, _noop2
                );
                _pairedRemainingAmt = IERC20(positionProps[_props.positionId].lendingPair).balanceOf(address(this));
            }
            IFraxlendPair(positionProps[_props.positionId].lendingPair).redeem(
                _pairedRemainingAmt, address(this), address(this)
            );
        }
    }

    function _processAndGetPairedTknAndAmt(
        uint256 _positionId,
        address _borrowedTkn,
        uint256 _borrowedAmt,
        bool _hasSelfLendingPairPod
    ) internal returns (address _finalPairedTkn, uint256 _finalPairedAmt) {
        _finalPairedTkn = _borrowedTkn;
        _finalPairedAmt = _borrowedAmt;
        address _lendingPair = positionProps[_positionId].lendingPair;
        if (_isPodSelfLending(_positionId)) {
            _finalPairedTkn = _lendingPair;
            IERC20(_borrowedTkn).safeIncreaseAllowance(_lendingPair, _finalPairedAmt);
            _finalPairedAmt = IFraxlendPair(_lendingPair).deposit(_finalPairedAmt, address(this));

            // self lending+podded
            if (_hasSelfLendingPairPod) {
                _finalPairedTkn = IDecentralizedIndex(positionProps[_positionId].pod).PAIRED_LP_TOKEN();
                IERC20(_lendingPair).safeIncreaseAllowance(_finalPairedTkn, _finalPairedAmt);
                IDecentralizedIndex(_finalPairedTkn).bond(_lendingPair, _finalPairedAmt, 0);
                _finalPairedAmt = IERC20(_finalPairedTkn).balanceOf(address(this));
            }
        }
    }

    function _unstakeAndRemoveLP(
        uint256 _positionId,
        address _pod,
        uint256 _collateralAssetRemoveAmt,
        uint256 _podAmtMin,
        uint256 _pairedAssetAmtMin
    ) internal returns (uint256 _podAmtReceived, uint256 _pairedAmtReceived) {
        address _spTKN = IDecentralizedIndex(_pod).lpStakingPool();
        address _pairedLpToken = IDecentralizedIndex(_pod).PAIRED_LP_TOKEN();

        uint256 _podAmtBefore = IERC20(_pod).balanceOf(address(this));
        uint256 _pairedTokenAmtBefore = IERC20(_pairedLpToken).balanceOf(address(this));

        uint256 _spTKNAmtReceived =
            IERC4626(_getAspTkn(_positionId)).redeem(_collateralAssetRemoveAmt, address(this), address(this));
        IERC20(_spTKN).safeIncreaseAllowance(address(indexUtils), _spTKNAmtReceived);
        indexUtils.unstakeAndRemoveLP(
            IDecentralizedIndex(_pod), _spTKNAmtReceived, _podAmtMin, _pairedAssetAmtMin, block.timestamp
        );
        _podAmtReceived = IERC20(_pod).balanceOf(address(this)) - _podAmtBefore;
        _pairedAmtReceived = IERC20(_pairedLpToken).balanceOf(address(this)) - _pairedTokenAmtBefore;
    }

    function _bondToPod(address _user, address _pod, uint256 _tknAmt, uint256 _amtPtknMintMin) internal {
        IDecentralizedIndex.IndexAssetInfo[] memory _podAssets = IDecentralizedIndex(_pod).getAllAssets();
        IERC20 _tkn = IERC20(_podAssets[0].token);
        uint256 _tknBalBefore = _tkn.balanceOf(address(this));
        _tkn.safeTransferFrom(_user, address(this), _tknAmt);
        uint256 _pTknBalBefore = IERC20(_pod).balanceOf(address(this));
        _tkn.approve(_pod, _tkn.balanceOf(address(this)) - _tknBalBefore);
        IDecentralizedIndex(_pod).bond(address(_tkn), _tkn.balanceOf(address(this)) - _tknBalBefore, _amtPtknMintMin);
        IERC20(_pod).balanceOf(address(this)) - _pTknBalBefore;
    }

    function _isPodSelfLending(uint256 _positionId) internal view returns (bool) {
        address _pod = positionProps[_positionId].pod;
        address _lendingPair = positionProps[_positionId].lendingPair;
        return IDecentralizedIndex(_pod).PAIRED_LP_TOKEN() != IFraxlendPair(_lendingPair).asset();
    }

    function _getBorrowTknForPod(uint256 _positionId) internal view returns (address) {
        return IFraxlendPair(positionProps[_positionId].lendingPair).asset();
    }

    function _getFlashSource(uint256 _positionId) internal view returns (address) {
        return flashSource[_getBorrowTknForPod(_positionId)];
    }

    function _getAspTkn(uint256 _positionId) internal view returns (address) {
        return IFraxlendPair(positionProps[_positionId].lendingPair).collateralContract();
    }

    function _getFlashDataAddLeverage(
        uint256 _positionId,
        address _sender,
        uint256 _pTknAmt,
        uint256 _pairedLpDesired,
        bytes memory _config
    ) internal view returns (bytes memory) {
        return abi.encode(
            LeverageFlashProps({
                method: FlashCallbackMethod.ADD,
                positionId: _positionId,
                owner: positionNFT.ownerOf(_positionId),
                sender: _sender,
                pTknAmt: _pTknAmt,
                pairedLpDesired: _pairedLpDesired,
                config: _config
            }),
            ""
        );
    }

    function setIndexUtils(IIndexUtils _utils) external onlyOwner {
        address _old = address(indexUtils);
        indexUtils = _utils;
        emit SetIndexUtils(_old, address(_utils));
    }

    function setFeeReceiver(address _receiver) external onlyOwner {
        address _currentReceiver = feeReceiver;
        feeReceiver = _receiver;
        emit SetFeeReceiver(_currentReceiver, _receiver);
    }

    function setOpenFeePerc(uint16 _newFee) external onlyOwner {
        require(_newFee <= 250, "MAX");
        uint16 _oldFee = openFeePerc;
        openFeePerc = _newFee;
        emit SetOpenFeePerc(_oldFee, _newFee);
    }

    function setCloseFeePerc(uint16 _newFee) external onlyOwner {
        require(_newFee <= 250, "MAX");
        uint16 _oldFee = closeFeePerc;
        closeFeePerc = _newFee;
        emit SetCloseFeePerc(_oldFee, _newFee);
    }

    function rescueETH() external onlyOwner {
        (bool _s,) = payable(_msgSender()).call{value: address(this).balance}("");
        require(_s, "S");
    }

    function rescueTokens(IERC20 _token) external onlyOwner {
        _token.safeTransfer(_msgSender(), _token.balanceOf(address(this)));
    }

    receive() external payable {}
}

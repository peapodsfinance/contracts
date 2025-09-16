// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/IDecentralizedIndex.sol";
import "../interfaces/IDexAdapter.sol";
import "../interfaces/IFlashLoanRecipient.sol";
import "../interfaces/IIndexUtils.sol";
import "../interfaces/ILeverageManager.sol";
import "../interfaces/ILeveragePositions.sol";
import {VaultAccount, VaultAccountingLibrary} from "../libraries/VaultAccount.sol";
import "./LeverageManagerAccessControl.sol";
import "./LeveragePositionCustodian.sol";

contract LeverageManager is Initializable, LeverageManagerAccessControl, ILeverageManager, IFlashLoanRecipient {
    using SafeERC20 for IERC20;
    using VaultAccountingLibrary for VaultAccount;

    /// @notice Used in calculations for various fees and percentage calculations
    uint16 constant PRECISION = 10000;

    /// @notice IndexUtils contract for handling LP operations and staking
    IIndexUtils public indexUtils;

    /// @notice Position NFT contract that manages leverage position ownership
    ILeveragePositions public positionNFT;

    /// @notice Address that receives protocol fees
    address public feeReceiver;

    /// @notice Fee percentage for opening positions (PRECISION, e.g., 100 = 1%)
    uint16 public openFeePerc;

    /// @notice Fee percentage for closing positions (PRECISION, e.g., 100 = 1%)
    uint16 public closeFeePerc;

    /// @notice Mapping from position ID to position properties
    /// @dev positionId => position props
    mapping(uint256 => LeveragePositionProps) public positionProps;

    /// @notice Private variable to track workflow initialization state
    bool private _workflowInitialized;

    /// @dev pod => partner address
    mapping(address => address) public partner;
    mapping(address => uint16) public partnerFeeOpen; // PRECISION, e.g., 100 = 1%
    mapping(address => uint16) public partnerFeeClose; // PRECISION, e.g., 100 = 1%
    mapping(address => uint256) public partnerExpiration; // timestamp when the partner will no longer receive fees

    /// @notice insurance wallet to receive open/close fees
    address public insurance;
    uint16 public insuranceFee; // PRECISION, e.g., 100 = 1%

    /// @notice Modifier to ensure only the position owner can perform certain actions
    /// @param _positionId The ID of the position to check ownership for
    modifier onlyPositionOwner(uint256 _positionId) {
        require(positionNFT.ownerOf(_positionId) == _msgSender(), "A0");
        _;
    }

    /// @notice Modifier to manage workflow state for add/remove leverage operations
    /// @param _starting True when starting a workflow, false when ending
    /// @dev Prevents reentrancy and ensures proper workflow state management
    modifier workflow(bool _starting) {
        if (_starting) {
            require(!_workflowInitialized, "W0");
            _workflowInitialized = true;
        } else {
            require(_workflowInitialized, "W1");
            _workflowInitialized = false;
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the LeverageManager contract with required dependencies
    /// @param _positionNFT Address of the position NFT contract
    /// @param _idxUtils Address of the IndexUtils contract
    /// @param _feeReceiver Address that will receive protocol fees
    function initialize(address _positionNFT, address _idxUtils, address _feeReceiver) public initializer {
        super.initialize();
        positionNFT = ILeveragePositions(_positionNFT);
        indexUtils = IIndexUtils(_idxUtils);
        feeReceiver = _feeReceiver;
    }

    /// @notice The ```initializePosition``` function initializes a new position and mints a new position NFT
    /// @param _pod The pod to leverage against for the new position
    /// @param _recipient User to receive the position NFT
    /// @param _hasSelfLendingPairPod bool Advanced implementation parameter that determines whether or not the self lending pod's paired LP asset (fTKN) is podded as well
    function initializePosition(address _pod, address _recipient, bool _hasSelfLendingPairPod)
        external
        override
        returns (uint256 _positionId)
    {
        _positionId = _initializePosition(_pod, _recipient, _hasSelfLendingPairPod);
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
    /// @param _borrowSharesAmt Amount of borrow shares to remove from the position by paying back
    /// @param _remLevConfig Extra config required for removing leverage
    /// @dev _config[0] == _collateralAssetRemoveAmt Amount of collateral asset to remove from the position
    /// @dev _config[1] == _podAmtMin Minimum Amount of pTKN to receive on remove LP transaction (slippage)
    /// @dev _config[2] == _pairedAssetAmtMin Minimum amount of pairedLpTkn to receive on remove LP transaction (slippage)
    /// @dev _config[3] == _podPairedLiquidityPrice18 If we need to swap pTKN for pairedLpTkn to pay back flash loan, this is a 10**18*token1/token0 (decimals NOT removed) price of pod LP
    /// @dev _config[4] == _userProvidedDebtAmt Amount of borrow token a user will use to transfer from their wallet to pay back flash loan
    function removeLeverage(uint256 _positionId, uint256 _borrowSharesAmt, bytes memory _remLevConfig)
        external
        override
        workflow(true)
    {
        address _sender = _msgSender();
        address _owner = positionNFT.ownerOf(_positionId);
        require(
            _owner == _sender || positionNFT.getApproved(_positionId) == _sender
                || positionNFT.isApprovedForAll(_owner, _sender),
            "A1"
        );

        address _lendingPair = positionProps[_positionId].lendingPair;
        IFraxlendPair(_lendingPair).addInterest(false);
        uint256 _borrowAmt = IFraxlendPair(_lendingPair).totalBorrow().toAmount(_borrowSharesAmt, true);
        (uint256 _userProvidedDebtAmt, bytes memory _finalRemLevConfig) =
            _checkAndResetRemoveLeverageConfigFromBorrowAmt(_borrowAmt, _remLevConfig);

        // if additional fees required for flash source, handle that here
        _processExtraFlashLoanPayment(_positionId, _sender);

        address _borrowTkn = _getBorrowTknForPosition(_positionId);

        // needed to repay lending pair asset before removing collateral and unwinding
        IERC20(_borrowTkn).safeIncreaseAllowance(_lendingPair, _borrowAmt);

        LeverageFlashProps memory _props;
        _props.method = FlashCallbackMethod.REMOVE;
        _props.positionId = _positionId;
        _props.owner = _owner;
        _props.sender = _sender;
        bytes memory _additionalInfo = abi.encode(_borrowSharesAmt, _finalRemLevConfig);
        if (_borrowAmt > _userProvidedDebtAmt) {
            IFlashLoanSource(_getFlashSource(_positionId)).flash(
                _borrowTkn, _borrowAmt - _userProvidedDebtAmt, address(this), abi.encode(_props, _additionalInfo)
            );
        } else {
            _callback(
                abi.encode(
                    IFlashLoanSource.FlashData(address(this), _borrowTkn, 0, abi.encode(_props, _additionalInfo), 0)
                )
            );
        }
    }

    /// @notice The ```borrowAssets``` function allows a position owner to borrow more for a position in the position custodian
    /// @param _positionId The NFT ID for the position
    /// @param _borrowAmt The amount of borrow token to borrow
    /// @param _collateralAmt A collateral amount to deposit
    /// @param _recipient Where the received assets should go
    function borrowAssets(uint256 _positionId, uint256 _borrowAmt, uint256 _collateralAmt, address _recipient)
        external
        onlyPositionOwner(_positionId)
    {
        if (_collateralAmt > 0) {
            IERC20(_getAspTkn(_positionId)).safeTransferFrom(
                _msgSender(), positionProps[_positionId].custodian, _collateralAmt
            );
        }
        LeveragePositionCustodian(positionProps[_positionId].custodian).borrowAsset(
            positionProps[_positionId].lendingPair,
            _borrowAmt,
            _collateralAmt,
            openFeePerc > 0 ? address(this) : _recipient
        );
        if (openFeePerc > 0) {
            address _borrowTkn = IFraxlendPair(positionProps[_positionId].lendingPair).asset();
            uint256 _openFeeAmt = (_borrowAmt * openFeePerc) / PRECISION;
            IERC20(_borrowTkn).safeTransfer(feeReceiver, _openFeeAmt);
            IERC20(_borrowTkn).safeTransfer(_recipient, _borrowAmt - _openFeeAmt);
        }
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
    function callback(bytes memory _userData) external override {
        IFlashLoanSource.FlashData memory _d = abi.decode(_userData, (IFlashLoanSource.FlashData));
        (LeverageFlashProps memory _posProps,) = abi.decode(_d.data, (LeverageFlashProps, bytes));
        require(_getFlashSource(_posProps.positionId) == _msgSender(), "A2");
        _callback(_userData);
    }

    /// @notice Internal callback function that handles flash loan callbacks for add/remove leverage operations
    /// @param _userData Encoded flash loan data containing position properties and additional information
    /// @dev This function is called after flash loan execution to complete leverage operations
    function _callback(bytes memory _userData) internal workflow(false) {
        IFlashLoanSource.FlashData memory _d = abi.decode(_userData, (IFlashLoanSource.FlashData));
        (LeverageFlashProps memory _posProps,) = abi.decode(_d.data, (LeverageFlashProps, bytes));

        address _pod = positionProps[_posProps.positionId].pod;

        if (_posProps.method == FlashCallbackMethod.ADD) {
            uint256 _ptknRefundAmt = _addLeveragePostCallback(_userData);
            if (_ptknRefundAmt > 0) {
                IERC20(_pod).safeTransfer(_posProps.owner, _ptknRefundAmt);
            }
        } else if (_posProps.method == FlashCallbackMethod.REMOVE) {
            (uint256 _ptknToUserAmt, uint256 _borrowTknToUser) = _removeLeveragePostCallback(_userData);
            if (_ptknToUserAmt > 0) {
                if (closeFeePerc > 0) {
                    uint256 _closePtknTotalFees = (_ptknToUserAmt * closeFeePerc) / PRECISION;
                    uint256 _closePtknTreasuryFees = _closePtknTotalFees;
                    if (partner[_pod] != address(0) && partnerFeeClose[_pod] > 0) {
                        uint256 _partnerAmt = (_closePtknTotalFees * partnerFeeClose[_pod]) / PRECISION;
                        IERC20(_pod).safeTransfer(partner[_pod], _partnerAmt);
                        _closePtknTreasuryFees -= _partnerAmt;
                    }
                    if (insurance != address(0) && insuranceFee > 0) {
                        uint256 _insPtknAmt = (_closePtknTotalFees * insuranceFee) / PRECISION;
                        IERC20(_pod).safeTransfer(insurance, _insPtknAmt);
                        _closePtknTreasuryFees -= _insPtknAmt;
                    }
                    IERC20(_pod).safeTransfer(feeReceiver, _closePtknTreasuryFees);
                    _ptknToUserAmt -= _closePtknTotalFees;
                }
                IERC20(_pod).safeTransfer(_posProps.owner, _ptknToUserAmt);
            }
            if (_borrowTknToUser > 0) {
                address _borrowTkn = _getBorrowTknForPosition(_posProps.positionId);
                if (closeFeePerc > 0) {
                    uint256 _closeBorrowTotalFees = (_borrowTknToUser * closeFeePerc) / PRECISION;
                    uint256 _closeBorrowTreasuryFees = _closeBorrowTotalFees;
                    if (partner[_pod] != address(0) && partnerFeeClose[_pod] > 0) {
                        uint256 _partnerAmt = (_closeBorrowTotalFees * partnerFeeClose[_pod]) / PRECISION;
                        IERC20(_borrowTkn).safeTransfer(partner[_pod], _partnerAmt);
                        _closeBorrowTreasuryFees -= _partnerAmt;
                    }
                    if (insurance != address(0) && insuranceFee > 0) {
                        uint256 _insBorrowAmt = (_closeBorrowTreasuryFees * insuranceFee) / PRECISION;
                        IERC20(_borrowTkn).safeTransfer(insurance, _insBorrowAmt);
                        _closeBorrowTreasuryFees -= _insBorrowAmt;
                    }
                    IERC20(_borrowTkn).safeTransfer(feeReceiver, _closeBorrowTreasuryFees);
                    _borrowTknToUser -= _closeBorrowTotalFees;
                }
                IERC20(_borrowTkn).safeTransfer(_posProps.owner, _borrowTknToUser);
            }
        } else {
            require(false, "NI");
        }
    }

    /// @notice Internal function to initialize a new leverage position
    /// @param _pod The pod address to create the position for
    /// @param _recipient The address that will receive the position NFT
    /// @param _hasSelfLendingPairPod Whether the self lending pod's paired LP asset is podded
    /// @return _positionId The ID of the newly created position
    function _initializePosition(address _pod, address _recipient, bool _hasSelfLendingPairPod)
        internal
        returns (uint256 _positionId)
    {
        _positionId = positionNFT.mint(_recipient);
        LeveragePositionCustodian _custodian = new LeveragePositionCustodian();
        positionProps[_positionId] = LeveragePositionProps({
            pod: _pod,
            lendingPair: lendingPairs[_pod],
            custodian: address(_custodian),
            isSelfLending: IDecentralizedIndex(_pod).PAIRED_LP_TOKEN() == lendingPairs[_pod],
            hasSelfLendingPairPod: _hasSelfLendingPairPod
        });
    }

    /// @notice Internal function to handle extra flash loan payment requirements
    /// @param _positionId The position ID to get flash source for
    /// @param _user The user address to transfer payment from
    /// @dev Some flash loan sources require additional payment tokens beyond the borrowed amount
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

    /// @notice Internal function to handle pre-callback logic for adding leverage
    /// @param _sender The address initiating the leverage addition
    /// @param _positionId The position ID (0 for new position)
    /// @param _pod The pod address for the position
    /// @param _pTknAmt Amount of pod tokens to use
    /// @param _pairedLpDesired Total amount of paired LP tokens desired
    /// @param _userProvidedDebtAmt Amount of debt token provided by user
    /// @param _hasSelfLendingPairPod Whether self lending pair pod is used
    /// @param _config Configuration parameters for the leverage operation
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
            _positionId = _initializePosition(_pod, _sender, _hasSelfLendingPairPod);
        } else {
            address _owner = positionNFT.ownerOf(_positionId);
            require(
                _owner == _sender || positionNFT.getApproved(_positionId) == _sender
                    || positionNFT.isApprovedForAll(_owner, _sender),
                "A3"
            );
            _pod = positionProps[_positionId].pod;
        }

        if (_userProvidedDebtAmt > 0) {
            IERC20(_getBorrowTknForPosition(_positionId)).safeTransferFrom(_sender, address(this), _userProvidedDebtAmt);
        }

        // if additional fees required for flash source, handle that here
        _processExtraFlashLoanPayment(_positionId, _sender);

        if (_pairedLpDesired > _userProvidedDebtAmt) {
            IFlashLoanSource(_getFlashSource(_positionId)).flash(
                _getBorrowTknForPosition(_positionId),
                _pairedLpDesired - _userProvidedDebtAmt,
                address(this),
                _getFlashDataAddLeverage(_positionId, _sender, _pTknAmt, _pairedLpDesired, _config)
            );
        } else {
            _callback(
                abi.encode(
                    IFlashLoanSource.FlashData(
                        address(this),
                        _getBorrowTknForPosition(_positionId),
                        0,
                        _getFlashDataAddLeverage(_positionId, _sender, _pTknAmt, _pairedLpDesired, _config),
                        0
                    )
                )
            );
        }
    }

    /// @notice Internal function to handle post-callback logic for adding leverage
    /// @param _data Encoded flash loan data containing position and configuration information
    /// @return _ptknRefundAmt Amount of pod tokens to refund to the user
    /// @dev Processes LP addition, staking, collateral deposit, and flash loan repayment
    function _addLeveragePostCallback(bytes memory _data) internal returns (uint256 _ptknRefundAmt) {
        IFlashLoanSource.FlashData memory _d = abi.decode(_data, (IFlashLoanSource.FlashData));
        (LeverageFlashProps memory _props,) = abi.decode(_d.data, (LeverageFlashProps, bytes));
        (uint256 _overrideBorrowAmt,,) = abi.decode(_props.config, (uint256, uint256, uint256));
        address _pod = positionProps[_props.positionId].pod;
        uint256 _borrowTknAmtToLp = _props.pairedLpDesired;
        // if there's an open fee send debt/borrow token to protocol
        if (openFeePerc > 0) {
            uint256 _openTotalFees = (_borrowTknAmtToLp * openFeePerc) / PRECISION;
            uint256 _openTreasuryFees = _openTotalFees;
            if (partner[_pod] != address(0) && partnerFeeOpen[_pod] > 0) {
                uint256 _partnerAmt = (_openTotalFees * partnerFeeOpen[_pod]) / PRECISION;
                IERC20(_d.token).safeTransfer(partner[_pod], _partnerAmt);
                _openTreasuryFees -= _partnerAmt;
            }
            if (insurance != address(0) && insuranceFee > 0) {
                uint256 _insAmt = (_openTotalFees * insuranceFee) / PRECISION;
                IERC20(_d.token).safeTransfer(insurance, _insAmt);
                _openTreasuryFees -= _insAmt;
            }
            IERC20(_d.token).safeTransfer(feeReceiver, _openTreasuryFees);
            _borrowTknAmtToLp -= _openTotalFees;
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
        if (_flashPaybackAmt > 0) {
            IERC20(_d.token).safeTransfer(
                IFlashLoanSource(_getFlashSource(_props.positionId)).source(), _flashPaybackAmt
            );
        }
        uint256 _remaining = IERC20(_d.token).balanceOf(address(this));
        if (_remaining != 0) {
            IERC20(_d.token).safeTransfer(positionNFT.ownerOf(_props.positionId), _remaining);
        }
        emit AddLeverage(_props.positionId, _props.owner, _pTknAmtUsed, _aspTknCollateralBal, _borrowAmt);
    }

    /// @notice Internal function to handle post-callback logic for removing leverage
    /// @param _userData Encoded flash loan data containing position and removal configuration
    /// @return _podAmtRemaining Amount of pod tokens remaining after removal
    /// @return _borrowAmtRemaining Amount of borrow tokens remaining after flash loan repayment
    /// @dev Processes collateral removal, LP unstaking, and flash loan repayment
    function _removeLeveragePostCallback(bytes memory _userData)
        internal
        returns (uint256 _podAmtRemaining, uint256 _borrowAmtRemaining)
    {
        IFlashLoanSource.FlashData memory _d = abi.decode(_userData, (IFlashLoanSource.FlashData));
        (LeverageFlashProps memory _props, bytes memory _additionalInfo) =
            abi.decode(_d.data, (LeverageFlashProps, bytes));
        (uint256 _borrowSharesToRepay, bytes memory _removeLevConfig) = abi.decode(_additionalInfo, (uint256, bytes));
        (uint256 _collateralAssetRemoveAmt,,,, uint256 _userProvidedDebtAmt) =
            abi.decode(_removeLevConfig, (uint256, uint256, uint256, uint256, uint256));

        if (_userProvidedDebtAmt > 0) {
            IERC20(_getBorrowTknForPosition(_props.positionId)).safeTransferFrom(
                _props.sender, address(this), _userProvidedDebtAmt
            );
        }

        LeveragePositionProps memory _posProps = positionProps[_props.positionId];

        // allowance increases for borrowAmt prior to flash loaning asset
        IFraxlendPair(_posProps.lendingPair).repayAsset(_borrowSharesToRepay, _posProps.custodian);
        LeveragePositionCustodian(_posProps.custodian).removeCollateral(
            _posProps.lendingPair, _collateralAssetRemoveAmt, address(this)
        );
        (uint256 _podAmtReceived, uint256 _pairedAmtReceived) =
            _unstakeAndRemoveLP(_props.positionId, _posProps.pod, _collateralAssetRemoveAmt, _removeLevConfig);
        _podAmtRemaining = _podAmtReceived;

        // redeem borrow asset from lending pair for self lending positions
        if (positionProps[_props.positionId].isSelfLending) {
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
        if (_repayAmount > _pairedAmtReceived) {
            uint256 _borrowAmtAcquired;
            (_podAmtRemaining, _borrowAmtAcquired) = _acquireBorrowTokenForRepayment(
                _props, _posProps.pod, _d.token, _repayAmount - _pairedAmtReceived, _podAmtReceived, _removeLevConfig
            );
            _pairedAmtReceived += _borrowAmtAcquired;
        }
        require(_pairedAmtReceived >= _repayAmount, "BAR");
        if (_repayAmount > 0) {
            IERC20(_d.token).safeTransfer(IFlashLoanSource(_getFlashSource(_props.positionId)).source(), _repayAmount);
        }
        _borrowAmtRemaining = _pairedAmtReceived - _repayAmount;
        emit RemoveLeverage(_props.positionId, _props.owner, _collateralAssetRemoveAmt);
    }

    /// @notice Internal function to debond tokens from a self-lending pod
    /// @param _pod The pod address to debond from
    /// @param _amount The amount of pod tokens to debond
    /// @return _amtOut The amount of underlying tokens received after debonding
    /// @dev Debonds 100% of the specified amount to the first underlying asset
    function _debondFromSelfLendingPod(address _pod, uint256 _amount) internal returns (uint256 _amtOut) {
        IDecentralizedIndex.IndexAssetInfo[] memory _podAssets = IDecentralizedIndex(_pod).getAllAssets();
        address[] memory _tokens = new address[](1);
        uint8[] memory _percentages = new uint8[](1);
        _tokens[0] = _podAssets[0].token;
        _percentages[0] = 100;
        IDecentralizedIndex(_pod).debond(_amount, _tokens, _percentages);
        _amtOut = IERC20(_tokens[0]).balanceOf(address(this));
    }

    /// @notice Internal function to acquire borrow tokens for flash loan repayment by swapping pod tokens
    /// @param _props Leverage flash properties containing position information
    /// @param _pod The pod address to swap tokens from
    /// @param _borrowToken The borrow token address needed for repayment
    /// @param _borrowNeeded The amount of borrow tokens needed
    /// @param _podAmtReceived The amount of pod tokens available for swapping
    /// @param _removeLevConf Configuration data for leverage removal
    /// @return _podAmtRemaining Amount of pod tokens remaining after swap
    /// @return _borrowAmtReceived Amount of borrow tokens acquired from swap
    /// @dev Handles both self-lending and regular lending scenarios
    function _acquireBorrowTokenForRepayment(
        LeverageFlashProps memory _props,
        address _pod,
        address _borrowToken,
        uint256 _borrowNeeded,
        uint256 _podAmtReceived,
        bytes memory _removeLevConf
    ) internal returns (uint256 _podAmtRemaining, uint256 _borrowAmtReceived) {
        _podAmtRemaining = _podAmtReceived;
        uint256 _borrowAmtNeededToSwap = _borrowNeeded;

        (,,, uint256 _podPairedLiquidityPrice18,) =
            abi.decode(_removeLevConf, (uint256, uint256, uint256, uint256, uint256));

        // sell pod token into LP for enough borrow token to get enough to repay
        // if self-lending swap for lending pair then redeem for borrow token
        if (_borrowAmtNeededToSwap > 0) {
            uint256 _borrowAmtFromSwap;
            if (positionProps[_props.positionId].isSelfLending) {
                address _lendingPair = positionProps[_props.positionId].lendingPair;
                (_podAmtRemaining, _borrowAmtFromSwap) = _swapPodForBorrowToken(
                    _pod,
                    _lendingPair,
                    _podAmtReceived,
                    IFraxlendPair(_lendingPair).convertToShares(_borrowAmtNeededToSwap),
                    _podPairedLiquidityPrice18
                );
                IFraxlendPair(_lendingPair).redeem(
                    IERC20(_lendingPair).balanceOf(address(this)), address(this), address(this)
                );
            } else {
                (_podAmtRemaining, _borrowAmtFromSwap) = _swapPodForBorrowToken(
                    _pod, _borrowToken, _podAmtReceived, _borrowAmtNeededToSwap, _podPairedLiquidityPrice18
                );
            }
            _borrowAmtReceived += _borrowAmtFromSwap;
        }
    }

    /// @notice Internal function to swap pod tokens for borrow tokens using DEX adapter
    /// @param _pod The pod token address to swap from
    /// @param _targetToken The target token address to swap to
    /// @param _podAmt The amount of pod tokens available for swapping
    /// @param _targetNeededAmt The amount of target tokens needed
    /// @param _podPairedLiquidityPrice18 Price of pod LP with 18 decimal precision
    /// @return _podRemainingAmt Amount of pod tokens remaining after swap
    /// @return _targetReceivedAmt Amount of target tokens received from swap
    /// @dev Uses price information to optimize swap amounts and includes slippage protection
    function _swapPodForBorrowToken(
        address _pod,
        address _targetToken,
        uint256 _podAmt,
        uint256 _targetNeededAmt,
        uint256 _podPairedLiquidityPrice18
    ) internal returns (uint256 _podRemainingAmt, uint256 _targetReceivedAmt) {
        IDexAdapter _dexAdapter = IDecentralizedIndex(_pod).DEX_HANDLER();
        uint256 _podBalBefore = IERC20(_pod).balanceOf(address(this));
        uint256 _podAmountIn = _podAmt;
        if (_podPairedLiquidityPrice18 > 0) {
            address _t1 = _pod < _targetToken ? _targetToken : _pod;
            uint256 _podAmountInExact = _targetToken == _t1
                ? (_targetNeededAmt * 10 ** 18) / _podPairedLiquidityPrice18
                : (_targetNeededAmt * _podPairedLiquidityPrice18) / 10 ** 18;
            _podAmountIn = (_podAmountInExact * 105) / 100; // add 5% to account for slippage/price impact
            _podAmountIn = _podAmountIn > _podAmt ? _podAmt : _podAmountIn;
        }
        IERC20(_pod).safeIncreaseAllowance(address(_dexAdapter), _podAmountIn);
        _targetReceivedAmt = _dexAdapter.swapV2Single(_pod, _targetToken, _podAmountIn, _targetNeededAmt, address(this));
        _podRemainingAmt = _podAmt - (_podBalBefore - IERC20(_pod).balanceOf(address(this)));
    }

    /// @notice Internal function to add liquidity to a pod and stake the LP tokens
    /// @param _borrowToken The borrowed token address used for LP
    /// @param _borrowAmt The amount of borrowed tokens to use for LP
    /// @param _props Leverage flash properties containing position and configuration data
    /// @return _pTknAmtUsed Amount of pod tokens used in the LP operation
    /// @return _pairedLpUsed Amount of paired LP tokens used in the operation
    /// @return _pairedLpLeftover Amount of paired LP tokens remaining after operation
    /// @dev Processes borrowed tokens into appropriate paired tokens and adds LP with staking
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

    /// @notice Internal function to convert staking pool tokens to ASP tokens and handle remaining paired assets
    /// @param _spTkn The staking pool token address
    /// @param _pairedRemainingAmt Amount of paired tokens remaining after LP operations
    /// @param _props Leverage flash properties containing position information
    /// @return _newAspTkns Amount of new ASP tokens created from staking pool tokens
    /// @dev Deposits staking tokens into ASP vault and handles self-lending pod redemptions
    function _spTknToAspTkn(address _spTkn, uint256 _pairedRemainingAmt, LeverageFlashProps memory _props)
        internal
        returns (uint256 _newAspTkns)
    {
        address _aspTkn = _getAspTkn(_props.positionId);
        uint256 _stakingBal = IERC20(_spTkn).balanceOf(address(this));
        IERC20(_spTkn).safeIncreaseAllowance(_aspTkn, _stakingBal);
        _newAspTkns = IERC4626(_aspTkn).deposit(_stakingBal, address(this));

        // for self lending pods redeem any extra paired LP asset back into main asset
        if (positionProps[_props.positionId].isSelfLending && _pairedRemainingAmt > 0) {
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

    /// @notice Internal function to validate and adjust remove leverage configuration based on borrow amount
    /// @param _borrowAmt The actual borrow amount to be repaid
    /// @param _remLevConfig The original remove leverage configuration
    /// @return _finalUserProvidedDebtAmt The adjusted user provided debt amount
    /// @return _finalRemLevConfig The adjusted remove leverage configuration
    /// @dev Ensures user provided debt amount doesn't exceed the actual borrow amount
    function _checkAndResetRemoveLeverageConfigFromBorrowAmt(uint256 _borrowAmt, bytes memory _remLevConfig)
        internal
        pure
        returns (uint256 _finalUserProvidedDebtAmt, bytes memory _finalRemLevConfig)
    {
        (uint256 _1, uint256 _2, uint256 _3, uint256 _4, uint256 _userProvidedDebtAmt) =
            abi.decode(_remLevConfig, (uint256, uint256, uint256, uint256, uint256));
        _finalUserProvidedDebtAmt = _userProvidedDebtAmt;
        if (_userProvidedDebtAmt > _borrowAmt) {
            _finalUserProvidedDebtAmt = _borrowAmt;
        }
        _finalRemLevConfig = abi.encode(_1, _2, _3, _4, _finalUserProvidedDebtAmt);
    }

    /// @notice Internal function to process borrowed tokens and convert them to appropriate paired tokens for LP
    /// @param _positionId The position ID to get lending pair information
    /// @param _borrowedTkn The borrowed token address
    /// @param _borrowedAmt The amount of borrowed tokens
    /// @param _hasSelfLendingPairPod Whether the self lending pair pod is used
    /// @return _finalPairedTkn The final paired token address for LP operations
    /// @return _finalPairedAmt The final amount of paired tokens for LP operations
    /// @dev Handles conversion for self-lending scenarios including podded lending pairs
    function _processAndGetPairedTknAndAmt(
        uint256 _positionId,
        address _borrowedTkn,
        uint256 _borrowedAmt,
        bool _hasSelfLendingPairPod
    ) internal returns (address _finalPairedTkn, uint256 _finalPairedAmt) {
        _finalPairedTkn = _borrowedTkn;
        _finalPairedAmt = _borrowedAmt;
        address _lendingPair = positionProps[_positionId].lendingPair;
        if (positionProps[_positionId].isSelfLending) {
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

    /// @notice Internal function to unstake LP tokens and remove liquidity from a pod
    /// @param _positionId The position ID to get ASP token information
    /// @param _pod The pod address to remove LP from
    /// @param _collateralAssetRemoveAmt Amount of collateral (ASP tokens) to remove
    /// @param _remLevConf Remove leverage configuration containing slippage parameters
    /// @return _podAmtReceived Amount of pod tokens received from LP removal
    /// @return _pairedAmtReceived Amount of paired tokens received from LP removal
    /// @dev Redeems ASP tokens for staking tokens, then unstakes and removes LP
    function _unstakeAndRemoveLP(
        uint256 _positionId,
        address _pod,
        uint256 _collateralAssetRemoveAmt,
        bytes memory _remLevConf
    ) internal returns (uint256 _podAmtReceived, uint256 _pairedAmtReceived) {
        (, uint256 _podAmtMin, uint256 _pairedAssetAmtMin,,) =
            abi.decode(_remLevConf, (uint256, uint256, uint256, uint256, uint256));
        address _spTkn = IDecentralizedIndex(_pod).lpStakingPool();
        address _pairedLpToken = IDecentralizedIndex(_pod).PAIRED_LP_TOKEN();

        uint256 _podAmtBefore = IERC20(_pod).balanceOf(address(this));
        uint256 _pairedTokenAmtBefore = IERC20(_pairedLpToken).balanceOf(address(this));

        uint256 _spTknAmtReceived =
            IERC4626(_getAspTkn(_positionId)).redeem(_collateralAssetRemoveAmt, address(this), address(this));
        IERC20(_spTkn).safeIncreaseAllowance(address(indexUtils), _spTknAmtReceived);
        indexUtils.unstakeAndRemoveLP(
            IDecentralizedIndex(_pod), _spTknAmtReceived, _podAmtMin, _pairedAssetAmtMin, block.timestamp
        );
        _podAmtReceived = IERC20(_pod).balanceOf(address(this)) - _podAmtBefore;
        _pairedAmtReceived = IERC20(_pairedLpToken).balanceOf(address(this)) - _pairedTokenAmtBefore;
    }

    /// @notice Internal function to bond underlying tokens to a pod to mint pod tokens
    /// @param _user The user address to transfer underlying tokens from
    /// @param _pod The pod address to bond tokens to
    /// @param _tknAmt The amount of underlying tokens to bond
    /// @param _amtPtknMintMin The minimum amount of pod tokens expected to be minted
    /// @dev Transfers underlying tokens from user and bonds them to the pod
    function _bondToPod(address _user, address _pod, uint256 _tknAmt, uint256 _amtPtknMintMin) internal {
        IDecentralizedIndex.IndexAssetInfo[] memory _podAssets = IDecentralizedIndex(_pod).getAllAssets();
        IERC20 _tkn = IERC20(_podAssets[0].token);
        uint256 _tknBalBefore = _tkn.balanceOf(address(this));
        _tkn.safeTransferFrom(_user, address(this), _tknAmt);
        uint256 _pTknBalBefore = IERC20(_pod).balanceOf(address(this));
        _tkn.safeIncreaseAllowance(_pod, _tkn.balanceOf(address(this)) - _tknBalBefore);
        IDecentralizedIndex(_pod).bond(address(_tkn), _tkn.balanceOf(address(this)) - _tknBalBefore, _amtPtknMintMin);
        IERC20(_pod).balanceOf(address(this)) - _pTknBalBefore;
    }

    /// @notice Internal view function to get the borrow token address for a position
    /// @param _positionId The position ID to get borrow token for
    /// @return The address of the borrow token (lending pair asset)
    function _getBorrowTknForPosition(uint256 _positionId) internal view returns (address) {
        return IFraxlendPair(positionProps[_positionId].lendingPair).asset();
    }

    /// @notice Internal view function to get the flash loan source address for a position
    /// @param _positionId The position ID to get flash source for
    /// @return The address of the flash loan source for the position's borrow token
    function _getFlashSource(uint256 _positionId) internal view returns (address) {
        return flashSource[_getBorrowTknForPosition(_positionId)];
    }

    /// @notice Internal view function to get the ASP token address for a position
    /// @param _positionId The position ID to get ASP token for
    /// @return The address of the ASP token (lending pair collateral contract)
    function _getAspTkn(uint256 _positionId) internal view returns (address) {
        return IFraxlendPair(positionProps[_positionId].lendingPair).collateralContract();
    }

    /// @notice Internal view function to encode flash loan data for adding leverage
    /// @param _positionId The position ID for the leverage operation
    /// @param _sender The address initiating the leverage addition
    /// @param _pTknAmt Amount of pod tokens to use
    /// @param _pairedLpDesired Total amount of paired LP tokens desired
    /// @param _config Configuration parameters for the leverage operation
    /// @return Encoded flash loan data for add leverage operation
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

    /// @notice Sets the position NFT contract address
    /// @param _posNFT The new position NFT contract address
    /// @dev Only callable by the contract owner
    function setPositionNFT(ILeveragePositions _posNFT) external onlyOwner {
        address _oldPosNFT = address(positionNFT);
        positionNFT = _posNFT;
        emit SetPositionsNFT(_oldPosNFT, address(_posNFT));
    }

    /// @notice Sets the IndexUtils contract address
    /// @param _utils The new IndexUtils contract address
    /// @dev Only callable by the contract owner
    function setIndexUtils(IIndexUtils _utils) external onlyOwner {
        address _old = address(indexUtils);
        indexUtils = _utils;
        emit SetIndexUtils(_old, address(_utils));
    }

    /// @notice Sets the fee receiver address
    /// @param _receiver The new fee receiver address
    /// @dev Only callable by the contract owner
    function setFeeReceiver(address _receiver) external onlyOwner {
        address _currentReceiver = feeReceiver;
        feeReceiver = _receiver;
        emit SetFeeReceiver(_currentReceiver, _receiver);
    }

    /// @notice Sets the opening fee percentage
    /// @param _newFee The new opening fee percentage (max 2500 = 25%)
    /// @dev Only callable by the contract owner, fee cannot exceed 25%
    function setOpenFeePerc(uint16 _newFee) external onlyOwner {
        require(_newFee <= 2500, "MAX");
        uint16 _oldFee = openFeePerc;
        openFeePerc = _newFee;
        emit SetOpenFeePerc(_oldFee, _newFee);
    }

    /// @notice Sets the closing fee percentage
    /// @param _newFee The new closing fee percentage (max 2500 = 25%)
    /// @dev Only callable by the contract owner, fee cannot exceed 25%
    function setCloseFeePerc(uint16 _newFee) external onlyOwner {
        require(_newFee <= 2500, "MAX");
        uint16 _oldFee = closeFeePerc;
        closeFeePerc = _newFee;
        emit SetCloseFeePerc(_oldFee, _newFee);
    }

    function setPartnerConfig(
        address _pod,
        address _partner,
        uint16 _partnerFeeOpen,
        uint16 _partnerFeeClose,
        uint256 _partnerExpiration
    ) external onlyOwner {
        require(_partnerFeeOpen <= 6000, "MAX1");
        require(_partnerFeeClose <= 6000, "MAX2");
        partner[_pod] = _partner;
        partnerFeeOpen[_pod] = _partnerFeeOpen;
        partnerFeeClose[_pod] = _partnerFeeClose;
        partnerExpiration[_pod] = _partnerExpiration;
        emit SetPartnerConfig(_pod, _partner, _partnerFeeOpen, _partnerFeeClose, _partnerExpiration);
    }

    function setInsuranceConfig(address _insuranceAddress, uint16 _insuranceFee) external onlyOwner {
        require(_insuranceFee <= 2500, "MAX");
        insurance = _insuranceAddress;
        insuranceFee = _insuranceFee;
        emit SetInsuranceConfig(_insuranceAddress, _insuranceFee);
    }

    /// @notice Emergency function to rescue ETH from the contract
    /// @dev Only callable by the contract owner
    function rescueETH() external onlyOwner {
        (bool _s,) = payable(_msgSender()).call{value: address(this).balance}("");
        require(_s, "S");
    }

    /// @notice Emergency function to rescue ERC20 tokens from the contract
    /// @param _token The ERC20 token contract to rescue
    /// @dev Only callable by the contract owner
    function rescueTokens(IERC20 _token) external onlyOwner {
        _token.safeTransfer(_msgSender(), _token.balanceOf(address(this)));
    }

    /// @dev Allow receiving ETH
    receive() external payable {}
}

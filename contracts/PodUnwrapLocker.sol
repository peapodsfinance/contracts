// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./interfaces/IDecentralizedIndex.sol";

/**
 * @title PodUnwrapLocker
 * @notice Allows users to debond from pods fee free with a time-lock period before they can withdraw their tokens.
 * The lock duration is determined by each pod's debondCooldown config setting. Users can withdraw early if they choose,
 * however they will realize a debondFee + 10% fee on early withdraw.
 */
contract PodUnwrapLocker is Context, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct LockInfo {
        address user;
        address pod;
        address[] tokens;
        uint256[] amounts;
        uint256 unlockTime;
        bool withdrawn;
    }

    // Protocol fee recipient
    address public immutable FEE_RECIPIENT_OWNABLE;

    // lock ID => lock info
    mapping(uint256 => LockInfo) public locks;
    uint256 public currentLockId;

    event LockCreated(
        uint256 indexed lockId,
        address indexed user,
        address indexed pod,
        address[] tokens,
        uint256[] amounts,
        uint256 unlockTime
    );
    event TokensWithdrawn(uint256 indexed lockId, address indexed user, address[] tokens, uint256[] amounts);
    event EarlyWithdrawal(
        uint256 indexed lockId, address indexed user, address[] tokens, uint256[] amounts, uint256 penalty
    );

    constructor(address _feeRecipient) {
        require(_feeRecipient != address(0), "F");
        FEE_RECIPIENT_OWNABLE = _feeRecipient;
    }

    /**
     * @notice Initiates the debonding process for a pod and creates a lock
     * @param _pod Address of the pod to debond from
     * @param _amount Amount of pod tokens to debond
     */
    function debondAndLock(address _pod, uint256 _amount) external nonReentrant {
        require(_amount > 0, "D1");
        require(_pod != address(0), "D2");

        IERC20(_pod).safeTransferFrom(_msgSender(), address(this), _amount);

        IDecentralizedIndex _podContract = IDecentralizedIndex(_pod);
        IDecentralizedIndex.IndexAssetInfo[] memory _podTokens = _podContract.getAllAssets();
        address[] memory _tokens = new address[](_podTokens.length);
        uint256[] memory _balancesBefore = new uint256[](_tokens.length);

        // Get token addresses and balances before debonding
        for (uint256 i = 0; i < _tokens.length; i++) {
            _tokens[i] = _podTokens[i].token;
            _balancesBefore[i] = IERC20(_tokens[i]).balanceOf(address(this));
        }
        _podContract.debond(_amount, new address[](0), new uint8[](0));

        uint256[] memory _receivedAmounts = new uint256[](_tokens.length);
        for (uint256 i = 0; i < _tokens.length; i++) {
            _receivedAmounts[i] = IERC20(_tokens[i]).balanceOf(address(this)) - _balancesBefore[i];
        }

        IDecentralizedIndex.Config memory _podConfig = _podContract.config();
        uint256 _lockId = currentLockId++;
        locks[_lockId] = LockInfo({
            user: _msgSender(),
            pod: _pod,
            tokens: _tokens,
            amounts: _receivedAmounts,
            unlockTime: block.timestamp + _podConfig.debondCooldown,
            withdrawn: false
        });

        emit LockCreated(
            _lockId, _msgSender(), _pod, _tokens, _receivedAmounts, block.timestamp + _podConfig.debondCooldown
        );
    }

    function withdraw(uint256 _lockId) external nonReentrant {
        _withdraw(_msgSender(), _lockId);
    }

    /**
     * @notice Allows early withdrawal with a penalty fee based on the pod's debond fee plus 10%
     * @param _lockId ID of the lock to withdraw early
     */
    function earlyWithdraw(uint256 _lockId) external nonReentrant {
        LockInfo storage _lock = locks[_lockId];

        // If already unlocked, use regular withdraw instead
        if (block.timestamp >= _lock.unlockTime) {
            _withdraw(_msgSender(), _lockId);
            return;
        }

        require(_lock.user == _msgSender(), "W1");
        require(!_lock.withdrawn, "W2");

        _lock.withdrawn = true;
        address _feeRecipient = Ownable(FEE_RECIPIENT_OWNABLE).owner();

        IDecentralizedIndex.Fees memory _podFees = IDecentralizedIndex(_lock.pod).fees();
        uint256 _debondFee = _podFees.debond;

        // Penalty = debond fee + 10%
        uint256 _penaltyBps = _debondFee + _debondFee / 10;
        uint256[] memory _penalizedAmounts = new uint256[](_lock.tokens.length);

        for (uint256 i = 0; i < _lock.tokens.length; i++) {
            if (_lock.amounts[i] > 0) {
                uint256 _penaltyAmount = (_lock.amounts[i] * _penaltyBps) / 10000;
                _penaltyAmount = _penaltyAmount == 0 && _debondFee > 0 ? 1 : _penaltyAmount;
                _penalizedAmounts[i] = _lock.amounts[i] - _penaltyAmount;
                if (_penaltyAmount > 0) {
                    IERC20(_lock.tokens[i]).safeTransfer(_feeRecipient, _penaltyAmount);
                }
                IERC20(_lock.tokens[i]).safeTransfer(_msgSender(), _penalizedAmounts[i]);
            }
        }

        emit EarlyWithdrawal(_lockId, _msgSender(), _lock.tokens, _penalizedAmounts, _penaltyBps);
    }

    /**
     * @notice Withdraws tokens after the lock period has expired
     * @param _lockId ID of the lock to withdraw
     */
    function _withdraw(address _user, uint256 _lockId) internal {
        LockInfo storage _lock = locks[_lockId];
        require(_lock.user == _user, "W1");
        require(!_lock.withdrawn, "W2");
        require(block.timestamp >= _lock.unlockTime, "W3");

        _lock.withdrawn = true;

        for (uint256 i = 0; i < _lock.tokens.length; i++) {
            if (_lock.amounts[i] > 0) {
                IERC20(_lock.tokens[i]).safeTransfer(_user, _lock.amounts[i]);
            }
        }

        emit TokensWithdrawn(_lockId, _user, _lock.tokens, _lock.amounts);
    }

    /**
     * @notice View function to get all information about a lock
     * @param _lockId ID of the lock to query
     */
    function getLockInfo(uint256 _lockId)
        external
        view
        returns (
            address user,
            address pod,
            address[] memory tokens,
            uint256[] memory amounts,
            uint256 unlockTime,
            bool withdrawn
        )
    {
        LockInfo storage _lock = locks[_lockId];
        return (_lock.user, _lock.pod, _lock.tokens, _lock.amounts, _lock.unlockTime, _lock.withdrawn);
    }
}

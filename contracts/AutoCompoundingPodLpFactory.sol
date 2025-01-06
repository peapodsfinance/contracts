// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./AutoCompoundingPodLp.sol";

contract AutoCompoundingPodLpFactory is Ownable {
    using SafeERC20 for IERC20;

    uint256 public minimumDepositAtCreation = 10 ** 3;

    event Create(address newAspTkn);

    event SetMinimumDepositAtCreation(uint256 olfFee, uint256 newFee);

    constructor() Ownable(_msgSender()) {}

    function create(
        string memory _name,
        string memory _symbol,
        bool _isSelfLendingPod,
        IDecentralizedIndex _pod,
        IDexAdapter _dexAdapter,
        IIndexUtils _indexUtils,
        uint96 _salt
    ) external returns (address _aspAddy) {
        _aspAddy =
            _deploy(getBytecode(_name, _symbol, _isSelfLendingPod, _pod, _dexAdapter, _indexUtils), _getFullSalt(_salt));
        if (address(_pod) != address(0) && minimumDepositAtCreation > 0) {
            _depositMin(_aspAddy, _pod);
        }
        AutoCompoundingPodLp(_aspAddy).transferOwnership(owner());
        emit Create(_aspAddy);
    }

    function _depositMin(address _aspAddy, IDecentralizedIndex _pod) internal {
        address _lpToken = _pod.lpStakingPool();
        IERC20(_lpToken).safeTransferFrom(_msgSender(), address(this), minimumDepositAtCreation);
        IERC20(_lpToken).safeIncreaseAllowance(_aspAddy, minimumDepositAtCreation);
        AutoCompoundingPodLp(_aspAddy).deposit(minimumDepositAtCreation, _msgSender());
    }

    function getNewCaFromParams(
        string memory _name,
        string memory _symbol,
        bool _isSelfLendingPod,
        IDecentralizedIndex _pod,
        IDexAdapter _dexAdapter,
        IIndexUtils _indexUtils,
        uint96 _salt
    ) external view returns (address) {
        bytes memory _bytecode = getBytecode(_name, _symbol, _isSelfLendingPod, _pod, _dexAdapter, _indexUtils);
        return getNewCaAddress(_bytecode, _salt);
    }

    function getBytecode(
        string memory _name,
        string memory _symbol,
        bool _isSelfLendingPod,
        IDecentralizedIndex _pod,
        IDexAdapter _dexAdapter,
        IIndexUtils _indexUtils
    ) public pure returns (bytes memory) {
        bytes memory _bytecode = type(AutoCompoundingPodLp).creationCode;
        return
            abi.encodePacked(_bytecode, abi.encode(_name, _symbol, _isSelfLendingPod, _pod, _dexAdapter, _indexUtils));
    }

    function getNewCaAddress(bytes memory _bytecode, uint96 _salt) public view returns (address) {
        bytes32 _hash =
            keccak256(abi.encodePacked(bytes1(0xff), address(this), _getFullSalt(_salt), keccak256(_bytecode)));
        return address(uint160(uint256(_hash)));
    }

    function _getFullSalt(uint96 _salt) internal view returns (uint256) {
        return uint256(uint160(address(this))) + _salt;
    }

    function _deploy(bytes memory _bytecode, uint256 _finalSalt) internal returns (address _addr) {
        assembly {
            _addr := create2(callvalue(), add(_bytecode, 0x20), mload(_bytecode), _finalSalt)
            if iszero(_addr) { revert(0, 0) }
        }
    }

    function setMinimumDepositAtCreation(uint256 _minDeposit) external onlyOwner {
        uint256 _oldDeposit = minimumDepositAtCreation;
        minimumDepositAtCreation = _minDeposit;
        emit SetMinimumDepositAtCreation(_oldDeposit, _minDeposit);
    }
}

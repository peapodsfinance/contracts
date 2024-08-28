// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import './AutoCompoundingPodLp.sol';

contract AutoCompoundingPodLpFactory is Ownable {
  using SafeERC20 for IERC20;

  uint256 minimumDepositAtCreation = 10 ** 3;

  event Create(address newAspTkn);

  function create(
    string memory _name,
    string memory _symbol,
    IDecentralizedIndex _pod,
    IDexAdapter _dexAdapter,
    IIndexUtils _utils,
    IRewardsWhitelister _whitelist,
    IV3TwapUtilities _v3TwapUtilities,
    uint256 _salt
  ) external onlyOwner {
    address _aspAddy = _deploy(
      getBytecode(
        _name,
        _symbol,
        _pod,
        _dexAdapter,
        _utils,
        _whitelist,
        _v3TwapUtilities
      ),
      _getFullSalt(_salt)
    );
    if (address(_pod) != address(0) && minimumDepositAtCreation > 0) {
      _depositMin(_aspAddy, _pod);
    }
    AutoCompoundingPodLp(_aspAddy).transferOwnership(_msgSender());
    emit Create(_aspAddy);
  }

  function _depositMin(address _aspAddy, IDecentralizedIndex _pod) internal {
    address _lpToken = _pod.lpStakingPool();
    IERC20(_lpToken).safeTransferFrom(
      _msgSender(),
      address(this),
      minimumDepositAtCreation
    );
    IERC20(_lpToken).safeApprove(_aspAddy, minimumDepositAtCreation);
    AutoCompoundingPodLp(_aspAddy).deposit(
      minimumDepositAtCreation,
      _msgSender()
    );
  }

  function getNewCaFromParams(
    string memory _name,
    string memory _symbol,
    IDecentralizedIndex _pod,
    IDexAdapter _dexAdapter,
    IIndexUtils _utils,
    IRewardsWhitelister _whitelist,
    IV3TwapUtilities _v3TwapUtilities,
    uint256 _salt
  ) external view returns (address) {
    bytes memory _bytecode = getBytecode(
      _name,
      _symbol,
      _pod,
      _dexAdapter,
      _utils,
      _whitelist,
      _v3TwapUtilities
    );
    return getNewCaAddress(_bytecode, _salt);
  }

  function getBytecode(
    string memory _name,
    string memory _symbol,
    IDecentralizedIndex _pod,
    IDexAdapter _dexAdapter,
    IIndexUtils _utils,
    IRewardsWhitelister _whitelist,
    IV3TwapUtilities _v3TwapUtilities
  ) public pure returns (bytes memory) {
    bytes memory _bytecode = type(AutoCompoundingPodLp).creationCode;
    return
      abi.encodePacked(
        _bytecode,
        abi.encode(
          _name,
          _symbol,
          _pod,
          _dexAdapter,
          _utils,
          _whitelist,
          _v3TwapUtilities
        )
      );
  }

  function getNewCaAddress(
    bytes memory _bytecode,
    uint256 _salt
  ) public view returns (address) {
    bytes32 _hash = keccak256(
      abi.encodePacked(
        bytes1(0xff),
        address(this),
        _getFullSalt(_salt),
        keccak256(_bytecode)
      )
    );
    return address(uint160(uint256(_hash)));
  }

  function _getFullSalt(uint256 _salt) internal view returns (uint256) {
    return uint256(uint160(address(this))) + _salt;
  }

  function _deploy(
    bytes memory _bytecode,
    uint256 _finalSalt
  ) internal returns (address _addr) {
    assembly {
      _addr := create2(
        callvalue(),
        add(_bytecode, 0x20),
        mload(_bytecode),
        _finalSalt
      )
      if iszero(extcodesize(_addr)) {
        revert(0, 0)
      }
    }
  }

  function setMinimumDepositAtCreation(uint256 _minDeposit) external onlyOwner {
    minimumDepositAtCreation = _minDeposit;
  }
}

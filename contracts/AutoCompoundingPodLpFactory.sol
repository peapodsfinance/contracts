// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import './AutoCompoundingPodLp.sol';

contract AutoCompoundingPodLpFactory is Ownable {
  using SafeERC20 for IERC20;

  uint256 minimumDepositAtCreation = 10 ** 9;

  event Create(address newAspTkn);

  function create(
    string memory _name,
    string memory _symbol,
    IDecentralizedIndex _pod,
    IDexAdapter _dexAdapter,
    IIndexUtils _utils,
    IRewardsWhitelister _whitelist,
    IV3TwapUtilities _v3TwapUtilities
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
      )
    );
    if (minimumDepositAtCreation > 0) {
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
    emit Create(_aspAddy);
  }

  function getNewCaFromParams(
    string memory _name,
    string memory _symbol,
    IDecentralizedIndex _pod,
    IDexAdapter _dexAdapter,
    IIndexUtils _utils,
    IRewardsWhitelister _whitelist,
    IV3TwapUtilities _v3TwapUtilities
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
    return getNewCaAddress(_bytecode);
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
    bytes memory _bytecode
  ) public view returns (address) {
    bytes32 _hash = keccak256(
      abi.encodePacked(
        bytes1(0xff),
        address(this),
        uint256(0) /* _salt */,
        keccak256(_bytecode)
      )
    );
    return address(uint160(uint256(_hash)));
  }

  function _deploy(bytes memory _bytecode) internal returns (address _addr) {
    assembly {
      _addr := create2(
        callvalue(),
        add(_bytecode, 0x20),
        mload(_bytecode),
        0 // _salt
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

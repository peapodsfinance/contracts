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
    AutoCompoundingPodLp _asp = new AutoCompoundingPodLp(
      _name,
      _symbol,
      _pod,
      _dexAdapter,
      _utils,
      _whitelist,
      _v3TwapUtilities
    );
    if (minimumDepositAtCreation > 0) {
      address _lpToken = _pod.lpStakingPool();
      IERC20(_lpToken).safeTransferFrom(
        _msgSender(),
        address(this),
        minimumDepositAtCreation
      );
      IERC20(_lpToken).safeApprove(address(_asp), minimumDepositAtCreation);
      _asp.deposit(minimumDepositAtCreation, _msgSender());
    }
    emit Create(address(_asp));
  }

  function setMinimumDepositAtCreation(uint256 _minDeposit) external onlyOwner {
    minimumDepositAtCreation = _minDeposit;
  }
}

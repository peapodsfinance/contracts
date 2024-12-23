// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./interfaces/IDecentralizedIndex.sol";
import "./interfaces/IStakingPoolToken.sol";
import "./interfaces/ITokenRewards.sol";

contract BulkPodYieldProcess is Context {
    using SafeERC20 for IERC20;

    function bulkTransferEmpty(IERC20[] memory _token) external {
        for (uint256 _i; _i < _token.length; _i++) {
            _token[_i].safeTransfer(address(this), 0);
        }
    }

    function bulkProcessPendingYield(IDecentralizedIndex[] memory _idx) external {
        for (uint256 _i; _i < _idx.length; _i++) {
            address _stakingPool = _idx[_i].lpStakingPool();
            address _rewards = IStakingPoolToken(_stakingPool).POOL_REWARDS();
            ITokenRewards(_rewards).depositFromPairedLpToken(0);
        }
    }
}

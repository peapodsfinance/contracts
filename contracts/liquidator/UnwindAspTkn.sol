// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IDecentralizedIndex} from "../interfaces/IDecentralizedIndex.sol";
import {IStakingPoolToken} from "../interfaces/IStakingPoolToken.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";

contract UnwindAspTkn {
    using SafeERC20 for IERC20;

    function unwindAspTkn(address _aspTkn, uint256 _amount) external {
        IERC20(_aspTkn).safeTransferFrom(msg.sender, address(this), _amount);
        IERC4626(_aspTkn).redeem(IERC20(_aspTkn).balanceOf(address(this)), address(this), address(this));
        address _spTkn = IERC4626(_aspTkn).asset();
        IStakingPoolToken(_spTkn).unstake(IERC20(_spTkn).balanceOf(address(this)));
        address _uniV2Tkn = IStakingPoolToken(_spTkn).stakingToken();
        address _pod = IStakingPoolToken(_spTkn).INDEX_FUND();
        if (IERC20(_uniV2Tkn).allowance(address(this), _pod) == 0) {
            IERC20(_uniV2Tkn).safeIncreaseAllowance(_pod, type(uint256).max);
        }
        IDecentralizedIndex(_pod).removeLiquidityV2(IERC20(_uniV2Tkn).balanceOf(address(this)), 0, 0, block.timestamp);
        IERC20(IUniswapV2Pair(_uniV2Tkn).token0()).safeTransfer(
            msg.sender, IERC20(IUniswapV2Pair(_uniV2Tkn).token0()).balanceOf(address(this))
        );
        IERC20(IUniswapV2Pair(_uniV2Tkn).token1()).safeTransfer(
            msg.sender, IERC20(IUniswapV2Pair(_uniV2Tkn).token1()).balanceOf(address(this))
        );
    }
}

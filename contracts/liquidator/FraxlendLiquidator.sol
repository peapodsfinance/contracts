// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IDecentralizedIndex} from "../interfaces/IDecentralizedIndex.sol";
import {IFraxlendPair} from "../interfaces/IFraxlendPair.sol";
import {IStakingPoolToken} from "../interfaces/IStakingPoolToken.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {VaultAccount, VaultAccountingLibrary} from "../libraries/VaultAccount.sol";

interface ILeverageManager {
    struct LeveragePositionProps {
        address pod;
        address lendingPair;
        address custodian;
        bool isSelfLending;
        bool hasSelfLendingPairPod;
    }

    function lendingPairs(address _pod) external view returns (address _lendingPair);

    function positionProps(uint256 _tokenId) external view returns (LeveragePositionProps calldata);
}

contract FraxlendLiquidator is Ownable {
    using SafeERC20 for IERC20;
    using VaultAccountingLibrary for VaultAccount;

    ILeverageManager public immutable LEVERAGE_MANAGER;

    constructor(address _lvfManager) Ownable(msg.sender) {
        LEVERAGE_MANAGER = ILeverageManager(_lvfManager);
    }

    function liquidate(uint256 _positionId, uint128 _sharesToLiquidate) external {
        ILeverageManager.LeveragePositionProps memory _props = LEVERAGE_MANAGER.positionProps(_positionId);
        _liquidate(_sharesToLiquidate, _props.lendingPair, _props.custodian);
    }

    function liquidateClean(uint256 _positionId) external {
        ILeverageManager.LeveragePositionProps memory _props = LEVERAGE_MANAGER.positionProps(_positionId);
        address _borrower = _props.custodian;
        _liquidate(
            uint128(IFraxlendPair(_props.lendingPair).userBorrowShares(_borrower)), _props.lendingPair, _props.custodian
        );
    }

    function liquidateDirectly(uint128 _sharesToLiquidate, address _lendingPair, address _borrower) external {
        _liquidate(_sharesToLiquidate, _lendingPair, _borrower);
    }

    function liquidateCleanDirectly(address _lendingPair, address _borrower) external {
        _liquidate(uint128(IFraxlendPair(_lendingPair).userBorrowShares(_borrower)), _lendingPair, _borrower);
    }

    function _liquidate(uint128 _sharesToLiquidate, address _lendingPair, address _borrower) internal {
        IFraxlendPair(_lendingPair).updateExchangeRate();
        (,,,,, VaultAccount memory _totalBorrow) = IFraxlendPair(_lendingPair).previewAddInterest();
        uint256 _amountAssets = _totalBorrow.toAmount(_sharesToLiquidate, true);
        address _asset = IFraxlendPair(_lendingPair).asset();

        IERC20(_asset).safeTransferFrom(msg.sender, address(this), _amountAssets);
        if (IERC20(_asset).allowance(address(this), _lendingPair) == 0) {
            IERC20(_asset).safeIncreaseAllowance(_lendingPair, type(uint256).max);
        }
        IFraxlendPair(_lendingPair).liquidate(_sharesToLiquidate, block.timestamp, _borrower);
        _unwindAspTkn(_lendingPair);
    }

    function _unwindAspTkn(address _lendingPair) internal {
        address _aspTkn = IFraxlendPair(_lendingPair).collateralContract();
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

    function rescueETH() external onlyOwner {
        (bool _sent,) = payable(owner()).call{value: address(this).balance}("");
        require(_sent);
    }

    function rescueERC20(IERC20 _token) external onlyOwner {
        require(_token.balanceOf(address(this)) > 0);
        _token.safeTransfer(owner(), _token.balanceOf(address(this)));
    }
}

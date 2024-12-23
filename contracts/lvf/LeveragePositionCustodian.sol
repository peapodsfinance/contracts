// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "../interfaces/IFraxlendPair.sol";

contract LeveragePositionCustodian is Context, Ownable {
    using SafeERC20 for IERC20;

    constructor() Ownable(_msgSender()) {}

    function borrowAsset(address _pair, uint256 _borrowAmount, uint256 _collateralAmount, address _receiver)
        external
        onlyOwner
    {
        IERC20(IFraxlendPair(_pair).collateralContract()).safeIncreaseAllowance(_pair, _collateralAmount);
        IFraxlendPair(_pair).borrowAsset(_borrowAmount, _collateralAmount, _receiver);
    }

    function removeCollateral(address _pair, uint256 _collateralAmount, address _receiver) external onlyOwner {
        IFraxlendPair(_pair).removeCollateral(_collateralAmount, _receiver);
    }

    function withdraw(address _token, address _recipient, uint256 _amount) external onlyOwner {
        _amount = _amount == 0 ? IERC20(_token).balanceOf(address(this)) : _amount;
        IERC20(_token).safeTransfer(_recipient, _amount);
    }
}

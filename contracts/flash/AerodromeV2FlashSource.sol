// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IAerodromePool.sol";
import "../interfaces/IAerodromePoolFactory.sol";
import "../interfaces/IFlashLoanRecipient.sol";
import "./FlashSourceBase.sol";

interface IAerodromeV2FlashSwapReceiver {
    function hook(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

contract AerodromeV2FlashSource is FlashSourceBase, IAerodromeV2FlashSwapReceiver {
    using SafeERC20 for IERC20;

    address public immutable override source;
    address public override paymentToken;
    uint256 public override paymentAmount;

    constructor(address _pool, address _lvfMan) FlashSourceBase(_lvfMan) {
        source = _pool;
    }

    function flash(address _token, uint256 _amount, address _recipient, bytes calldata _data)
        external
        override
        workflow(true)
        onlyLeverageManager
    {
        FlashData memory _fData = FlashData(_recipient, _token, _amount, _data, 0);
        (uint256 _borrowAmount0, uint256 _borrowAmount1) =
            _token == IAerodromePool(source).token0() ? (_amount, uint256(0)) : (uint256(0), _amount);
        IAerodromePool(source).swap(_borrowAmount0, _borrowAmount1, address(this), abi.encode(_fData));
    }

    function hook(address, uint256 _amount0, uint256 _amount1, bytes calldata _data) external override workflow(false) {
        require(_msgSender() == source, "CBV");
        FlashData memory _fData = abi.decode(_data, (FlashData));
        _fData.fee = _fData.token == IAerodromePool(source).token0()
            ? (_amount0 * 10000)
                / (10000 - IAerodromePoolFactory(IAerodromePool(source).factory()).getFee(msg.sender, false)) - _amount0
            : (_amount1 * 10000)
                / (10000 - IAerodromePoolFactory(IAerodromePool(source).factory()).getFee(msg.sender, false)) - _amount1;
        IERC20(_fData.token).safeTransfer(_fData.recipient, _fData.amount);
        IFlashLoanRecipient(_fData.recipient).callback(abi.encode(_fData));
    }
}

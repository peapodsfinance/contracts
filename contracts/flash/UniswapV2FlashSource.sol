// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../interfaces/IFlashLoanRecipient.sol";
import "./FlashSourceBase.sol";

interface IUniswapV2FlashSwapReceiver {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}

contract UniswapV2FlashSource is FlashSourceBase, IUniswapV2FlashSwapReceiver {
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
            _token == IUniswapV2Pair(source).token0() ? (_amount, uint256(0)) : (uint256(0), _amount);
        IUniswapV2Pair(source).swap(_borrowAmount0, _borrowAmount1, address(this), abi.encode(_fData));
    }

    function uniswapV2Call(address, uint256 _amount0, uint256 _amount1, bytes calldata _data)
        external
        override
        workflow(false)
    {
        require(_msgSender() == source, "CBV");
        FlashData memory _fData = abi.decode(_data, (FlashData));
        _fData.fee = _fData.token == IUniswapV2Pair(source).token0()
            ? (_amount0 * 1000) / 997 - _amount0
            : (_amount1 * 1000) / 997 - _amount1;
        IERC20(_fData.token).safeTransfer(_fData.recipient, _fData.amount);
        IFlashLoanRecipient(_fData.recipient).callback(abi.encode(_fData));
    }
}

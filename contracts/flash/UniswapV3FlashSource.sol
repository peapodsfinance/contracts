// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3FlashCallback.sol";
import "../interfaces/IFlashLoanRecipient.sol";
import "./FlashSourceBase.sol";

// https://solidity-by-example.org/defi/uniswap-v3-flash/
contract UniswapV3FlashSource is FlashSourceBase, IUniswapV3FlashCallback {
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
            _token == IUniswapV3Pool(source).token0() ? (_amount, uint256(0)) : (uint256(0), _amount);
        IUniswapV3Pool(source).flash(address(this), _borrowAmount0, _borrowAmount1, abi.encode(_fData));
    }

    function uniswapV3FlashCallback(uint256 _fee0, uint256 _fee1, bytes calldata _data)
        external
        override
        workflow(false)
    {
        require(_msgSender() == source, "CBV");
        FlashData memory _fData = abi.decode(_data, (FlashData));
        _fData.fee = _fData.token == IUniswapV3Pool(source).token0() ? _fee0 : _fee1;
        IERC20(_fData.token).safeTransfer(_fData.recipient, _fData.amount);
        IFlashLoanRecipient(_fData.recipient).callback(abi.encode(_fData));
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IFlashLoanRecipient} from "../interfaces/IFlashLoanRecipient.sol";
import {FlashSourceBase} from "./FlashSourceBase.sol";

contract UniswapV4FlashSource is FlashSourceBase, IUnlockCallback {
    using SafeERC20 for IERC20;

    address public immutable override source;
    address public override paymentToken;
    uint256 public override paymentAmount;

    constructor(address _poolManager, address _lvfMan) FlashSourceBase(_lvfMan) {
        source = _poolManager;
    }

    function flash(address _token, uint256 _amount, address _recipient, bytes calldata _data)
        external
        override
        workflow(true)
        onlyLeverageManager
    {
        FlashData memory _fData = FlashData(_recipient, _token, _amount, _data, 0);
        IPoolManager(source).unlock(abi.encode(_fData));
    }

    function unlockCallback(bytes calldata _data) external returns (bytes memory) {
        require(_msgSender() == source, "CBV");
        FlashData memory _fData = abi.decode(_data, (FlashData));
        IPoolManager(source).take(Currency.wrap(_fData.token), _fData.recipient, _fData.amount);
        IPoolManager(source).sync(Currency.wrap(_fData.token));
        IFlashLoanRecipient(_fData.recipient).callback(abi.encode(_fData));
        IPoolManager(source).settle();
    }
}

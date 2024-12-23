// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import "../interfaces/IERC20Bridgeable.sol";
import "../interfaces/ICCIPTokenRouter.sol";
import "../interfaces/ICCIPTokenBridge.sol";

contract TokenBridge is ICCIPTokenBridge, CCIPReceiver, Context {
    using SafeERC20 for IERC20Bridgeable;

    IRouterClient public immutable ccipRouter;
    ICCIPTokenRouter public immutable tokenRouter;

    constructor(IRouterClient _ccipRouter, ICCIPTokenRouter _tokenRouter) CCIPReceiver(address(_ccipRouter)) {
        ccipRouter = _ccipRouter;
        tokenRouter = _tokenRouter;
    }

    function bridgeTokens(uint64 _chainSelector, address _tokenReceiver, address _token, uint256 _amount)
        external
        payable
        returns (bytes32 _messageId)
    {
        require(tokenRouter.globalEnabled(), "GLDISABLED");
        ICCIPTokenRouter.TokenConfig memory _bridgeConf = tokenRouter.getConfig(_token, _chainSelector);
        require(_bridgeConf.enabled, "BRDISABLED");
        uint256 _amountActual = _processInboundTokens(_token, _msgSender(), _amount, _bridgeConf.sourceTokenMintBurn);
        (Client.EVM2AnyMessage memory _evm2AnyMessage, uint256 _nativeFees) =
            _getMessageFee(_bridgeConf, _tokenReceiver, _amountActual);
        require(msg.value >= _nativeFees, "FEES");

        uint256 _refund = msg.value - _nativeFees;
        if (_refund > 0) {
            (bool _wasRef,) = payable(_msgSender()).call{value: _refund}("");
            require(_wasRef, "REFUND");
        }
        _messageId = ccipRouter.ccipSend{value: _nativeFees}(_chainSelector, _evm2AnyMessage);
        emit TokensSent(_messageId, _chainSelector, _tokenReceiver, _token, _amount, _amountActual, _nativeFees);
        return _messageId;
    }

    function getMessageFee(ICCIPTokenRouter.TokenConfig memory _bridgeConf, address _tokenReceiver, uint256 _amount)
        external
        view
        returns (uint256)
    {
        (, uint256 _fee) = _getMessageFee(_bridgeConf, _tokenReceiver, _amount);
        return _fee;
    }

    function _getMessageFee(ICCIPTokenRouter.TokenConfig memory _bridgeConf, address _tokenReceiver, uint256 _amount)
        internal
        view
        returns (Client.EVM2AnyMessage memory, uint256)
    {
        Client.EVM2AnyMessage memory _evm2AnyMessage = _buildMsg(_bridgeConf, _tokenReceiver, _amount);
        return (_evm2AnyMessage, ccipRouter.getFee(_bridgeConf.targetChain, _evm2AnyMessage));
    }

    function _buildMsg(ICCIPTokenRouter.TokenConfig memory _bridgeConf, address _tokenReceiver, uint256 _amount)
        internal
        view
        returns (Client.EVM2AnyMessage memory)
    {
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_bridgeConf.targetBridge),
            data: abi.encode(
                TokenTransfer({tokenReceiver: _tokenReceiver, targetToken: _bridgeConf.targetToken, amount: _amount})
            ),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: tokenRouter.targetChainGasLimit()})),
            feeToken: address(0) // native
        });
        return evm2AnyMessage;
    }

    function _ccipReceive(Client.Any2EVMMessage memory _message) internal override {
        require(tokenRouter.globalEnabled(), "GLDISABLED");
        TokenTransfer memory _tokenTransferInfo = abi.decode(_message.data, (TokenTransfer));
        ICCIPTokenRouter.TokenConfig memory _bridgeConf =
            tokenRouter.getConfig(_tokenTransferInfo.targetToken, _message.sourceChainSelector);
        require(_bridgeConf.enabled, "BRDISABLED");
        require(abi.decode(_message.sender, (address)) == _bridgeConf.targetBridge, "AUTH");
        address _user = _tokenTransferInfo.tokenReceiver;
        address _token = _tokenTransferInfo.targetToken;
        uint256 _amount = _tokenTransferInfo.amount;
        _processOutboundTokens(_token, _user, _amount, _bridgeConf.sourceTokenMintBurn);
        emit TokensReceived(_message.messageId, _message.sourceChainSelector, _user, _token, _amount);
    }

    function _processInboundTokens(address _token, address _user, uint256 _amount, bool _isMintBurn)
        internal
        returns (uint256)
    {
        uint256 _bal = IERC20Bridgeable(_token).balanceOf(address(this));
        IERC20Bridgeable(_token).safeTransferFrom(_user, address(this), _amount);
        uint256 _amountAfter = IERC20Bridgeable(_token).balanceOf(address(this)) - _bal;
        if (_isMintBurn) {
            IERC20Bridgeable(_token).burn(_amount);
        }
        return _amountAfter;
    }

    function _processOutboundTokens(address _token, address _user, uint256 _amount, bool _isMintBurn) internal {
        if (_isMintBurn) {
            IERC20Bridgeable(_token).mint(_user, _amount);
        } else {
            IERC20Bridgeable(_token).safeTransfer(_user, _amount);
        }
    }
}

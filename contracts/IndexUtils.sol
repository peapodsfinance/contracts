// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./interfaces/IDecentralizedIndex.sol";
import "./interfaces/IDexAdapter.sol";
import "./interfaces/IIndexUtils.sol";
import "./interfaces/IStakingPoolToken.sol";
import "./interfaces/ITokenRewards.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV3Pool.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IWETH.sol";
import "./Zapper.sol";

contract IndexUtils is Context, IIndexUtils, Zapper {
    using SafeERC20 for IERC20;

    constructor(IV3TwapUtilities _v3TwapUtilities, IDexAdapter _dexAdapter) Zapper(_v3TwapUtilities, _dexAdapter) {}

    function bond(IDecentralizedIndex _indexFund, address _token, uint256 _amount, uint256 _amountMintMin) external {
        IDecentralizedIndex.IndexAssetInfo[] memory _assets = _indexFund.getAllAssets();
        uint256[] memory _balsBefore = new uint256[](_assets.length);

        uint256 _tokenCurSupply = _indexFund.totalAssets(_token);
        uint256 _tokenAmtSupplyRatioX96 =
            _indexFund.totalSupply() == 0 ? FixedPoint96.Q96 : (_amount * FixedPoint96.Q96) / _tokenCurSupply;
        uint256 _al = _assets.length;
        for (uint256 _i; _i < _al; _i++) {
            uint256 _amountNeeded = _indexFund.totalSupply() == 0
                ? _indexFund.getInitialAmount(_token, _amount, _assets[_i].token)
                : (_indexFund.totalAssets(_assets[_i].token) * _tokenAmtSupplyRatioX96) / FixedPoint96.Q96;
            _balsBefore[_i] = IERC20(_assets[_i].token).balanceOf(address(this));
            IERC20(_assets[_i].token).safeTransferFrom(_msgSender(), address(this), _amountNeeded);
            IERC20(_assets[_i].token).safeIncreaseAllowance(address(_indexFund), _amountNeeded);
        }
        uint256 _idxBalBefore = IERC20(_indexFund).balanceOf(address(this));
        _indexFund.bond(_token, _amount, _amountMintMin);
        IERC20(_indexFund).safeTransfer(_msgSender(), IERC20(_indexFund).balanceOf(address(this)) - _idxBalBefore);

        // refund any excess tokens to user we didn't use to bond
        for (uint256 _i; _i < _al; _i++) {
            _checkAndRefundERC20(_msgSender(), _assets[_i].token, _balsBefore[_i]);
        }
    }

    function addLPAndStake(
        IDecentralizedIndex _indexFund,
        uint256 _amountIdxTokens,
        address _pairedLpTokenProvided,
        uint256 _amtPairedLpTokenProvided,
        uint256 _amountPairedLpTokenMin,
        uint256 _slippage,
        uint256 _deadline
    ) external payable override returns (uint256 _amountOut) {
        address _indexFundAddy = address(_indexFund);
        address _pairedLpToken = _indexFund.PAIRED_LP_TOKEN();
        uint256 _idxTokensBefore = IERC20(_indexFundAddy).balanceOf(address(this));
        uint256 _pairedLpTokenBefore = IERC20(_pairedLpToken).balanceOf(address(this));
        uint256 _ethBefore = address(this).balance - msg.value;
        IERC20(_indexFundAddy).safeTransferFrom(_msgSender(), address(this), _amountIdxTokens);
        if (_pairedLpTokenProvided == address(0)) {
            require(msg.value > 0, "NEEDETH");
            _amtPairedLpTokenProvided = msg.value;
        } else {
            IERC20(_pairedLpTokenProvided).safeTransferFrom(_msgSender(), address(this), _amtPairedLpTokenProvided);
        }
        if (_pairedLpTokenProvided != _pairedLpToken) {
            _zap(_pairedLpTokenProvided, _pairedLpToken, _amtPairedLpTokenProvided, _amountPairedLpTokenMin);
        }

        IERC20(_pairedLpToken).safeIncreaseAllowance(
            _indexFundAddy, IERC20(_pairedLpToken).balanceOf(address(this)) - _pairedLpTokenBefore
        );

        // keeping 1 wei of each asset on the CA reduces transfer gas cost due to non-zero storage
        // so worth it to keep 1 wei in the CA if there's not any here already
        _amountOut = _indexFund.addLiquidityV2(
            IERC20(_indexFundAddy).balanceOf(address(this)) - (_idxTokensBefore == 0 ? 1 : _idxTokensBefore),
            IERC20(_pairedLpToken).balanceOf(address(this)) - (_pairedLpTokenBefore == 0 ? 1 : _pairedLpTokenBefore),
            _slippage,
            _deadline
        );
        require(_amountOut > 0, "LPM");

        IERC20(DEX_ADAPTER.getV2Pool(_indexFundAddy, _pairedLpToken)).safeIncreaseAllowance(
            _indexFund.lpStakingPool(), _amountOut
        );
        _amountOut = _stakeLPForUserHandlingLeftoverCheck(_indexFund.lpStakingPool(), _msgSender(), _amountOut);

        // refunds if needed for index tokens and pairedLpToken
        if (address(this).balance > _ethBefore) {
            (bool _s,) = payable(_msgSender()).call{value: address(this).balance - _ethBefore}("");
            require(_s && address(this).balance >= _ethBefore, "TOOMUCH");
        }
        _checkAndRefundERC20(_msgSender(), _indexFundAddy, _idxTokensBefore == 0 ? 1 : _idxTokensBefore);
        _checkAndRefundERC20(_msgSender(), _pairedLpToken, _pairedLpTokenBefore == 0 ? 1 : _pairedLpTokenBefore);
    }

    function unstakeAndRemoveLP(
        IDecentralizedIndex _indexFund,
        uint256 _amountStakedTokens,
        uint256 _minLPTokens,
        uint256 _minPairedLpToken,
        uint256 _deadline
    ) external override {
        address _stakingPool = _indexFund.lpStakingPool();
        address _pairedLpToken = _indexFund.PAIRED_LP_TOKEN();
        uint256 _stakingBalBefore = IERC20(_stakingPool).balanceOf(address(this));
        uint256 _pairedLpTokenBefore = IERC20(_pairedLpToken).balanceOf(address(this));
        IERC20(_stakingPool).safeTransferFrom(_msgSender(), address(this), _amountStakedTokens);
        uint256 _indexBalBefore = _unstakeAndRemoveLP(
            _indexFund,
            _stakingPool,
            IERC20(_stakingPool).balanceOf(address(this)) - _stakingBalBefore,
            _minLPTokens,
            _minPairedLpToken,
            _deadline
        );
        if (IERC20(address(_indexFund)).balanceOf(address(this)) > _indexBalBefore) {
            IERC20(address(_indexFund)).safeTransfer(
                _msgSender(), IERC20(address(_indexFund)).balanceOf(address(this)) - _indexBalBefore
            );
        }
        if (IERC20(_pairedLpToken).balanceOf(address(this)) > _pairedLpTokenBefore) {
            IERC20(_pairedLpToken).safeTransfer(
                _msgSender(), IERC20(_pairedLpToken).balanceOf(address(this)) - _pairedLpTokenBefore
            );
        }
    }

    function claimRewardsMulti(address[] memory _rewards) external {
        uint256 _rl = _rewards.length;
        for (uint256 _i; _i < _rl; _i++) {
            ITokenRewards(_rewards[_i]).claimReward(_msgSender());
        }
    }

    /// @dev the ERC20 approval for the input token to stake has already been approved
    function _stakeLPForUserHandlingLeftoverCheck(address _stakingPool, address _receiver, uint256 _stakeAmount)
        internal
        returns (uint256 _finalAmountOut)
    {
        _finalAmountOut = _stakeAmount;
        if (IERC20(_stakingPool).balanceOf(address(this)) > 0) {
            IStakingPoolToken(_stakingPool).stake(_receiver, _stakeAmount);
            return _finalAmountOut;
        }

        IStakingPoolToken(_stakingPool).stake(address(this), _stakeAmount);
        // leave 1 wei in the CA for future gas savings
        _finalAmountOut = IERC20(_stakingPool).balanceOf(address(this)) - 1;
        IERC20(_stakingPool).safeTransfer(_receiver, _finalAmountOut);
    }

    function _unstakeAndRemoveLP(
        IDecentralizedIndex _indexFund,
        address _stakingPool,
        uint256 _unstakeAmount,
        uint256 _minLPTokens,
        uint256 _minPairedLpTokens,
        uint256 _deadline
    ) internal returns (uint256 _fundTokensBefore) {
        address _pairedLpToken = _indexFund.PAIRED_LP_TOKEN();
        address _v2Pool = DEX_ADAPTER.getV2Pool(address(_indexFund), _pairedLpToken);
        uint256 _v2TokensBefore = IERC20(_v2Pool).balanceOf(address(this));
        IStakingPoolToken(_stakingPool).unstake(_unstakeAmount);

        _fundTokensBefore = _indexFund.balanceOf(address(this));
        IERC20(_v2Pool).safeIncreaseAllowance(
            address(_indexFund), IERC20(_v2Pool).balanceOf(address(this)) - _v2TokensBefore
        );
        _indexFund.removeLiquidityV2(
            IERC20(_v2Pool).balanceOf(address(this)) - _v2TokensBefore, _minLPTokens, _minPairedLpTokens, _deadline
        );
    }

    function _bondToRecipient(
        IDecentralizedIndex _indexFund,
        address _indexToken,
        uint256 _bondTokens,
        uint256 _amountMintMin,
        address _recipient
    ) internal returns (uint256) {
        uint256 _idxTokensBefore = IERC20(address(_indexFund)).balanceOf(address(this));
        IERC20(_indexToken).safeIncreaseAllowance(address(_indexFund), _bondTokens);
        _indexFund.bond(_indexToken, _bondTokens, _amountMintMin);
        uint256 _idxTokensGained = IERC20(address(_indexFund)).balanceOf(address(this)) - _idxTokensBefore;
        if (_recipient != address(this)) {
            IERC20(address(_indexFund)).safeTransfer(_recipient, _idxTokensGained);
        }
        return _idxTokensGained;
    }

    function _checkAndRefundERC20(address _user, address _asset, uint256 _beforeBal) internal {
        uint256 _curBal = IERC20(_asset).balanceOf(address(this));
        if (_curBal > _beforeBal) {
            IERC20(_asset).safeTransfer(_user, _curBal - _beforeBal);
        }
    }
}

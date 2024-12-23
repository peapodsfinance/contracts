// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import "../interfaces/ICamelotPair.sol";
import "../interfaces/ICamelotRouter.sol";
import "../interfaces/ISwapRouterAlgebra.sol";
import "../interfaces/IUniswapV2Factory.sol";
import "../interfaces/IV3TwapUtilities.sol";
import "./UniswapDexAdapter.sol";

contract CamelotDexAdapter is UniswapDexAdapter {
    using SafeERC20 for IERC20;

    IUniswapV2Router02 constant V2_ROUTER_UNI = IUniswapV2Router02(0x02b7D3D5438037D49A25ed15ae34F2d0099494B5);

    constructor(IV3TwapUtilities _v3TwapUtilities, address _v2Router, address _v3Router)
        UniswapDexAdapter(_v3TwapUtilities, _v2Router, _v3Router, true)
    {}

    function getV3Pool(address _token0, address _token1, uint24) external view override returns (address) {
        return V3_TWAP_UTILS.getV3Pool(IPeripheryImmutableState(V3_ROUTER).factory(), _token0, _token1);
    }

    function getReserves(address _pool) external view virtual override returns (uint112 _reserve0, uint112 _reserve1) {
        (_reserve0, _reserve1,,) = ICamelotPair(_pool).getReserves();
    }

    function swapV2Single(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _recipient
    ) external override returns (uint256 _amountOut) {
        uint256 _outBefore = IERC20(_tokenOut).balanceOf(_recipient);
        if (_amountIn == 0) {
            _amountIn = IERC20(_tokenIn).balanceOf(address(this));
        } else {
            IERC20(_tokenIn).safeTransferFrom(_msgSender(), address(this), _amountIn);
        }
        address[] memory _path = new address[](2);
        _path[0] = _tokenIn;
        _path[1] = _tokenOut;
        IERC20(_tokenIn).safeIncreaseAllowance(V2_ROUTER, _amountIn);
        ICamelotRouter(V2_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn, _amountOutMin, _path, _recipient, Ownable(address(V3_TWAP_UTILS)).owner(), block.timestamp
        );
        return IERC20(_tokenOut).balanceOf(_recipient) - _outBefore;
    }

    function swapV2SingleExactOut(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountInMax,
        uint256 _amountOut,
        address _recipient
    ) external virtual override returns (uint256 _amountInUsed) {
        uint256 _inBefore = IERC20(_tokenIn).balanceOf(address(this));
        if (_amountInMax == 0) {
            _amountInMax = IERC20(_tokenIn).balanceOf(address(this));
        } else {
            IERC20(_tokenIn).safeTransferFrom(_msgSender(), address(this), _amountInMax);
        }
        address[] memory _path = new address[](2);
        _path[0] = _tokenIn;
        _path[1] = _tokenOut;
        IERC20(_tokenIn).safeIncreaseAllowance(address(V2_ROUTER_UNI), _amountInMax);
        V2_ROUTER_UNI.swapTokensForExactTokens(_amountOut, _amountInMax, _path, _recipient, block.timestamp);
        uint256 _inRemaining = IERC20(_tokenIn).balanceOf(address(this)) - _inBefore;
        if (_inRemaining > 0) {
            IERC20(_tokenIn).safeTransfer(_msgSender(), _inRemaining);
        }
        _amountInUsed = _amountInMax - _inRemaining;
    }

    function swapV3Single(
        address _tokenIn,
        address _tokenOut,
        uint24,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _recipient
    ) external override returns (uint256 _amountOut) {
        uint256 _outBefore = IERC20(_tokenOut).balanceOf(_recipient);
        if (_amountIn == 0) {
            _amountIn = IERC20(_tokenIn).balanceOf(address(this));
        } else {
            IERC20(_tokenIn).safeTransferFrom(_msgSender(), address(this), _amountIn);
        }
        IERC20(_tokenIn).safeIncreaseAllowance(V3_ROUTER, _amountIn);
        ISwapRouterAlgebra(V3_ROUTER).exactInputSingle(
            ISwapRouterAlgebra.ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                recipient: _recipient,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: _amountOutMin,
                limitSqrtPrice: 0
            })
        );
        return IERC20(_tokenOut).balanceOf(_recipient) - _outBefore;
    }
}

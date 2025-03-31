// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "../interfaces/IShadowV2Factory.sol";
import "../interfaces/IShadowV2Router.sol";
import "../interfaces/ISwapRouterShadow.sol";
import "./UniswapDexAdapter.sol";

contract ShadowDexAdapter is UniswapDexAdapter {
    using SafeERC20 for IERC20;

    address immutable V3_FACTORY;

    constructor(IV3TwapUtilities _v3TwapUtilities, address _v2Router, address _v3Router, address _v3Factory)
        UniswapDexAdapter(_v3TwapUtilities, _v2Router, _v3Router, false)
    {
        V3_FACTORY = _v3Factory;
    }

    function getV3Pool(address _token0, address _token1, int24 _tickSpacing)
        external
        view
        virtual
        override
        returns (address)
    {
        return V3_TWAP_UTILS.getV3Pool(V3_FACTORY, _token0, _token1, _tickSpacing);
    }

    function getV3Pool(address, address, uint24) external view virtual override returns (address _p) {
        _p;
        require(false, "I0");
    }

    function getV2Pool(address _token0, address _token1) external view virtual override returns (address) {
        return IShadowV2Factory(IShadowV2Router(V2_ROUTER).factory()).getPair(_token0, _token1, false);
    }

    function createV2Pool(address _token0, address _token1) external virtual override returns (address) {
        return IShadowV2Factory(IShadowV2Router(V2_ROUTER).factory()).createPair(_token0, _token1, false);
    }

    function swapV2Single(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _recipient
    ) external virtual override returns (uint256 _amountOut) {
        uint256 _outBefore = IERC20(_tokenOut).balanceOf(_recipient);
        if (_amountIn == 0) {
            _amountIn = IERC20(_tokenIn).balanceOf(address(this));
        } else {
            IERC20(_tokenIn).safeTransferFrom(_msgSender(), address(this), _amountIn);
        }
        IShadowV2Router.route[] memory _path = new IShadowV2Router.route[](1);
        _path[0].from = _tokenIn;
        _path[0].to = _tokenOut;
        IERC20(_tokenIn).safeIncreaseAllowance(V2_ROUTER, _amountIn);
        IShadowV2Router(V2_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn, _amountOutMin, _path, _recipient, block.timestamp
        );
        return IERC20(_tokenOut).balanceOf(_recipient) - _outBefore;
    }

    function swapV3Single(address, address, uint24, uint256, uint256, address)
        external
        virtual
        override
        returns (uint256 _amountOut)
    {
        _amountOut;
        require(false, "NI3");
    }

    function swapV3Single(
        address _tokenIn,
        address _tokenOut,
        int24 _tickSpacing,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _recipient
    ) external virtual override returns (uint256 _amountOut) {
        uint256 _outBefore = IERC20(_tokenOut).balanceOf(_recipient);
        if (_amountIn == 0) {
            _amountIn = IERC20(_tokenIn).balanceOf(address(this));
        } else {
            IERC20(_tokenIn).safeTransferFrom(_msgSender(), address(this), _amountIn);
        }
        IERC20(_tokenIn).safeIncreaseAllowance(V3_ROUTER, _amountIn);
        ISwapRouterShadow(V3_ROUTER).exactInputSingle(
            ISwapRouterShadow.ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                tickSpacing: _tickSpacing,
                recipient: _recipient,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: _amountOutMin,
                sqrtPriceLimitX96: 0
            })
        );
        return IERC20(_tokenOut).balanceOf(_recipient) - _outBefore;
    }

    function addLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _amountADesired,
        uint256 _amountBDesired,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _to,
        uint256 _deadline
    ) external virtual override {
        uint256 _aBefore = IERC20(_tokenA).balanceOf(address(this));
        uint256 _bBefore = IERC20(_tokenB).balanceOf(address(this));
        IERC20(_tokenA).safeTransferFrom(_msgSender(), address(this), _amountADesired);
        IERC20(_tokenB).safeTransferFrom(_msgSender(), address(this), _amountBDesired);
        IERC20(_tokenA).safeIncreaseAllowance(V2_ROUTER, _amountADesired);
        IERC20(_tokenB).safeIncreaseAllowance(V2_ROUTER, _amountBDesired);
        IShadowV2Router(V2_ROUTER).addLiquidity(
            _tokenA, _tokenB, false, _amountADesired, _amountBDesired, _amountAMin, _amountBMin, _to, _deadline
        );
        if (IERC20(_tokenA).balanceOf(address(this)) > _aBefore) {
            IERC20(_tokenA).safeTransfer(_to, IERC20(_tokenA).balanceOf(address(this)) - _aBefore);
        }
        if (IERC20(_tokenB).balanceOf(address(this)) > _bBefore) {
            IERC20(_tokenB).safeTransfer(_to, IERC20(_tokenB).balanceOf(address(this)) - _bBefore);
        }
    }

    function removeLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _liquidity,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _to,
        uint256 _deadline
    ) external virtual override {
        address _pool = IShadowV2Factory(IShadowV2Router(V2_ROUTER).factory()).getPair(_tokenA, _tokenB, false);
        uint256 _lpBefore = IERC20(_pool).balanceOf(address(this));
        IERC20(_pool).safeTransferFrom(_msgSender(), address(this), _liquidity);
        IERC20(_pool).safeIncreaseAllowance(V2_ROUTER, _liquidity);
        IShadowV2Router(V2_ROUTER).removeLiquidity(
            _tokenA, _tokenB, false, _liquidity, _amountAMin, _amountBMin, _to, _deadline
        );
        if (IERC20(_pool).balanceOf(address(this)) > _lpBefore) {
            IERC20(_pool).safeTransfer(_to, IERC20(_pool).balanceOf(address(this)) - _lpBefore);
        }
    }
}

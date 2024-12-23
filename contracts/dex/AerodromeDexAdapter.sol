// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import "../interfaces/IAerodromeLpSugar.sol";
import "../interfaces/IAerodromeVoter.sol";
import "../interfaces/IAerodromePoolFactory.sol";
import "../interfaces/IAerodromePool.sol";
import "../interfaces/IAerodromeRouter.sol";
import "../interfaces/IAerodromeUniversalRouter.sol";
import "../interfaces/IV3TwapUtilities.sol";
import "./UniswapDexAdapter.sol";
import {AerodromeCommands} from "../libraries/AerodromeCommands.sol";

contract AerodromeDexAdapter is UniswapDexAdapter {
    using SafeERC20 for IERC20;

    address constant CL_FACTORY = 0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A;
    int24 constant TICK_SPACING = 200;

    constructor(IV3TwapUtilities _v3TwapUtilities, address _v2Router, address _v3Router)
        UniswapDexAdapter(_v3TwapUtilities, _v2Router, _v3Router, true)
    {}

    function WETH() external view virtual override returns (address) {
        return address(IAerodromeRouter(V2_ROUTER).weth());
    }

    function getV3Pool(address _token0, address _token1, int24 _tickSpacing) external view override returns (address) {
        return V3_TWAP_UTILS.getV3Pool(CL_FACTORY, _token0, _token1, _tickSpacing);
    }

    function getV3Pool(address, address, uint24) external view virtual override returns (address _p) {
        _p;
        require(false, "I0");
    }

    function getV2Pool(address _token0, address _token1) public view override returns (address) {
        return IAerodromePoolFactory(IAerodromeRouter(V2_ROUTER).defaultFactory()).getPool(_token0, _token1, 0);
    }

    function getReserves(address _pool) external view virtual override returns (uint112 _reserve0, uint112 _reserve1) {
        (uint256 __reserve0, uint256 __reserve1,) = IAerodromePool(_pool).getReserves();
        _reserve0 = uint112(__reserve0);
        _reserve1 = uint112(__reserve1);
    }

    function createV2Pool(address _token0, address _token1) external override returns (address) {
        return IAerodromePoolFactory(IAerodromeRouter(V2_ROUTER).defaultFactory()).createPool(_token0, _token1, 0);
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
        IAerodromeRouter.Route[] memory _routes = new IAerodromeRouter.Route[](1);
        _routes[0] = IAerodromeRouter.Route({
            from: _tokenIn,
            to: _tokenOut,
            stable: false,
            factory: IAerodromeRouter(V2_ROUTER).defaultFactory()
        });
        IERC20(_tokenIn).safeIncreaseAllowance(V2_ROUTER, _amountIn);
        IAerodromeRouter(V2_ROUTER).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amountIn, _amountOutMin, _routes, _recipient, block.timestamp
        );

        return IERC20(_tokenOut).balanceOf(_recipient) - _outBefore;
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
        bytes memory _commands = abi.encodePacked(bytes1(uint8(AerodromeCommands.V3_SWAP_EXACT_IN)));
        bytes[] memory _inputs = new bytes[](1);
        bytes memory _path = abi.encodePacked(_tokenIn, TICK_SPACING, _tokenOut);
        _inputs[0] = abi.encode(_recipient, _amountIn, _amountOutMin, _path, true);
        IAerodromeUniversalRouter(V3_ROUTER).execute(_commands, _inputs, block.timestamp);

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
        IAerodromeRouter(V2_ROUTER).addLiquidity(
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
        address _pool = IAerodromePoolFactory(IAerodromeRouter(V2_ROUTER).defaultFactory()).getPool(_tokenA, _tokenB, 0);
        uint256 _lpBefore = IERC20(_pool).balanceOf(address(this));
        IERC20(_pool).safeTransferFrom(_msgSender(), address(this), _liquidity);
        IERC20(_pool).safeIncreaseAllowance(V2_ROUTER, _liquidity);
        IAerodromeRouter(V2_ROUTER).removeLiquidity(
            _tokenA, _tokenB, false, _liquidity, _amountAMin, _amountBMin, _to, _deadline
        );
        if (IERC20(_pool).balanceOf(address(this)) > _lpBefore) {
            IERC20(_pool).safeTransfer(_to, IERC20(_pool).balanceOf(address(this)) - _lpBefore);
        }
    }
}

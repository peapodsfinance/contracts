// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';
import '@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import './interfaces/IUniswapV2Pair.sol';
import './interfaces/IUniswapV3Pool.sol';
import './interfaces/IUniswapV2Router02.sol';
import './interfaces/IV3TwapUtilities.sol';
import './interfaces/IWETH.sol';
import './interfaces/IZapper.sol';

contract Zapper is IZapper, Context, Ownable {
  using SafeERC20 for IERC20;

  address constant V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  address immutable V2_ROUTER;
  address immutable WETH;
  IV3TwapUtilities immutable V3_TWAP_UTILS;

  uint256 _slippage = 30; // 3%

  // token in => token out => swap pool(s)
  mapping(address => mapping(address => Pools)) public zapMap;

  constructor(address _v2Router, IV3TwapUtilities _v3TwapUtilities) {
    V2_ROUTER = _v2Router;
    V3_TWAP_UTILS = _v3TwapUtilities;
    WETH = IUniswapV2Router02(V2_ROUTER).WETH();

    // WETH/DAI
    _setZapMapFromPoolSingle(
      PoolType.V3,
      0x60594a405d53811d3BC4766596EFD80fd545A270
    );
    // WETH/USDC
    _setZapMapFromPoolSingle(
      PoolType.V3,
      0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640
    );
    // WETH/OHM
    _setZapMapFromPoolSingle(
      PoolType.V3,
      0x88051B0eea095007D3bEf21aB287Be961f3d8598
    );
    // USDC/OHM
    _setZapMapFromPoolSingle(
      PoolType.V3,
      0x893f503FaC2Ee1e5B78665db23F9c94017Aae97D
    );
  }

  function _zap(
    address _in,
    address _out,
    uint256 _amountIn,
    uint256 _amountOutMin
  ) internal returns (uint256 _amountOut) {
    if (_in == address(0)) {
      _amountIn = _ethToWETH(_amountIn);
      _in = WETH;
    }
    Pools memory _poolInfo = zapMap[_in][_out];
    // no pool so just try to swap over one path univ2
    if (_poolInfo.pool1 == address(0)) {
      address[] memory _path = new address[](2);
      _path[0] = _in;
      _path[1] = _out;
      return _swapV2(_path, _amountIn, _amountOutMin);
    }

    bool _twoHops = _poolInfo.pool2 != address(0);
    if (_poolInfo.poolType == PoolType.V2) {
      // univ2
      address _token0 = IUniswapV2Pair(_poolInfo.pool1).token0();
      address[] memory _path = new address[](_twoHops ? 3 : 2);
      _path[0] = _in;
      _path[1] = !_twoHops ? _out : _token0 == _in
        ? IUniswapV2Pair(_poolInfo.pool1).token1()
        : _token0;
      if (_twoHops) {
        _path[2] = _out;
      }
      return _swapV2(_path, _amountIn, _amountOutMin);
    } else {
      // univ3
      if (_twoHops) {
        address _t0 = IUniswapV3Pool(_poolInfo.pool1).token0();
        return
          _swapV3Multi(
            _in,
            IUniswapV3Pool(_poolInfo.pool1).fee(),
            _t0 == _in ? IUniswapV3Pool(_poolInfo.pool1).token0() : _t0,
            IUniswapV3Pool(_poolInfo.pool2).fee(),
            _out,
            _amountIn,
            _amountOutMin
          );
      } else {
        return
          _swapV3Single(
            _in,
            IUniswapV3Pool(_poolInfo.pool1).fee(),
            _out,
            _amountIn,
            _amountOutMin
          );
      }
    }
  }

  function _ethToWETH(uint256 _amountETH) internal returns (uint256) {
    uint256 _wethBal = IERC20(WETH).balanceOf(address(this));
    IWETH(WETH).deposit{ value: _amountETH }();
    return IERC20(WETH).balanceOf(address(this)) - _wethBal;
  }

  function _swapV3Single(
    address _in,
    uint24 _fee,
    address _out,
    uint256 _amountIn,
    uint256 _amountOutMin
  ) internal returns (uint256 _amountOut) {
    if (_amountOutMin == 0) {
      address _v3Pool = V3_TWAP_UTILS.getV3Pool(
        IPeripheryImmutableState(V3_ROUTER).factory(),
        _in,
        _out,
        _fee
      );
      address _token0 = _in < _out ? _in : _out;
      uint256 _poolPriceX96 = V3_TWAP_UTILS.priceX96FromSqrtPriceX96(
        V3_TWAP_UTILS.sqrtPriceX96FromPoolAndInterval(_v3Pool)
      );
      _amountOutMin = _in == _token0
        ? (_poolPriceX96 * _amountIn) / FixedPoint96.Q96
        : (_amountIn * FixedPoint96.Q96) / _poolPriceX96;
    }

    uint256 _outBefore = IERC20(_out).balanceOf(address(this));
    IERC20(_in).safeIncreaseAllowance(V3_ROUTER, _amountIn);
    ISwapRouter(V3_ROUTER).exactInputSingle(
      ISwapRouter.ExactInputSingleParams({
        tokenIn: _in,
        tokenOut: _out,
        fee: _fee,
        recipient: address(this),
        deadline: block.timestamp,
        amountIn: _amountIn,
        amountOutMinimum: (_amountOutMin * (1000 - _slippage)) / 1000,
        sqrtPriceLimitX96: 0
      })
    );
    return IERC20(_out).balanceOf(address(this)) - _outBefore;
  }

  function _swapV3Multi(
    address _in,
    uint24 _fee1,
    address _in2,
    uint24 _fee2,
    address _out,
    uint256 _amountIn,
    uint256 _amountOutMin
  ) internal returns (uint256) {
    uint256 _outBefore = IERC20(_out).balanceOf(address(this));
    IERC20(_in).safeIncreaseAllowance(V3_ROUTER, _amountIn);
    bytes memory _path = abi.encodePacked(_in, _fee1, _in2, _fee2, _out);
    ISwapRouter(V3_ROUTER).exactInput(
      ISwapRouter.ExactInputParams({
        path: _path,
        recipient: address(this),
        deadline: block.timestamp,
        amountIn: _amountIn,
        amountOutMinimum: _amountOutMin
      })
    );
    return IERC20(_out).balanceOf(address(this)) - _outBefore;
  }

  function _swapV2(
    address[] memory _path,
    uint256 _amountIn,
    uint256 _amountOutMin
  ) internal returns (uint256) {
    address _out = _path.length == 3 ? _path[2] : _path[1];
    uint256 _outBefore = IERC20(_out).balanceOf(address(this));
    IERC20(_path[0]).safeIncreaseAllowance(V2_ROUTER, _amountIn);
    IUniswapV2Router02(V2_ROUTER)
      .swapExactTokensForTokensSupportingFeeOnTransferTokens(
        _amountIn,
        _amountOutMin,
        _path,
        address(this),
        block.timestamp
      );
    return IERC20(_out).balanceOf(address(this)) - _outBefore;
  }

  function _setZapMapFromPoolSingle(PoolType _type, address _pool) internal {
    address _t0 = IUniswapV3Pool(_pool).token0();
    address _t1 = IUniswapV3Pool(_pool).token1();
    Pools memory _poolConf = Pools({
      poolType: _type,
      pool1: _pool,
      pool2: address(0)
    });
    zapMap[_t0][_t1] = _poolConf;
    zapMap[_t1][_t0] = _poolConf;
  }

  function setSlippage(uint256 _slip) external onlyOwner {
    _slippage = _slip;
  }

  function setZapMap(
    address _in,
    address _out,
    Pools memory _pools
  ) external onlyOwner {
    zapMap[_in][_out] = _pools;
  }

  function setZapMapFromPoolSingle(
    PoolType _type,
    address _pool
  ) external onlyOwner {
    _setZapMapFromPoolSingle(_type, _pool);
  }

  function rescueETH() external onlyOwner {
    (bool _sent, ) = payable(owner()).call{ value: address(this).balance }('');
    require(_sent);
  }

  function rescueERC20(IERC20 _token) external onlyOwner {
    _token.safeTransfer(owner(), _token.balanceOf(address(this)));
  }

  receive() external payable {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';
import '../interfaces/IERC20Metadata.sol';
import '../interfaces/IAlgebraFactory.sol';
import '../interfaces/IAlgebraKimV3Pool.sol';
import '../interfaces/IV3TwapUtilities.sol';
import '../libraries/FullMath.sol';
import '../libraries/PoolAddressKimMode.sol';
import '../libraries/TickMath.sol';

contract V3TwapKimUtilities is IV3TwapUtilities, Ownable {
  uint32 constant INTERVAL = 10 minutes;

  function getV3Pool(
    address _v3Factory,
    address _t0,
    address _t1
  ) external view override returns (address) {
    (address _token0, address _token1) = _t0 < _t1 ? (_t0, _t1) : (_t1, _t0);
    PoolAddressKimMode.PoolKey memory _key = PoolAddressKimMode.PoolKey({
      token0: _token0,
      token1: _token1
    });
    return
      PoolAddressKimMode.computeAddress(
        IAlgebraFactory(_v3Factory).poolDeployer(),
        _key
      );
  }

  function getV3Pool(
    address,
    address,
    address,
    int24
  ) external pure override returns (address) {
    require(false, 'I0');
    return address(0);
  }

  function getV3Pool(
    address,
    address,
    address,
    uint24
  ) external pure override returns (address) {
    require(false, 'I1');
    return address(0);
  }

  function getPoolPriceUSDX96(
    address _pricePool,
    address _nativeStablePool,
    address _WETH9
  ) public view override returns (uint256) {
    address _token0 = IAlgebraKimV3Pool(_nativeStablePool).token0();
    uint256 _priceStableWETH9X96 = _adjustedPriceX96(
      IAlgebraKimV3Pool(_nativeStablePool),
      _token0 == _WETH9
        ? IAlgebraKimV3Pool(_nativeStablePool).token1()
        : _token0
    );
    if (_pricePool == _nativeStablePool) {
      return _priceStableWETH9X96;
    }
    uint256 _priceMainX96 = _adjustedPriceX96(
      IAlgebraKimV3Pool(_pricePool),
      _WETH9
    );
    return (_priceStableWETH9X96 * _priceMainX96) / FixedPoint96.Q96;
  }

  function sqrtPriceX96FromPoolAndInterval(
    address _poolAddress
  ) public view override returns (uint160 sqrtPriceX96) {
    sqrtPriceX96 = _sqrtPriceX96FromPoolAndInterval(_poolAddress);
  }

  function sqrtPriceX96FromPoolAndPassedInterval(
    address _poolAddress,
    uint32
  ) external view override returns (uint160 sqrtPriceX96) {
    sqrtPriceX96 = _sqrtPriceX96FromPoolAndInterval(_poolAddress);
  }

  function _sqrtPriceX96FromPoolAndInterval(
    address _poolAddress
  ) internal view returns (uint160 sqrtPriceX96) {
    IAlgebraKimV3Pool _pool = IAlgebraKimV3Pool(_poolAddress);
    // TODO: find and use tickCumulative method
    (sqrtPriceX96, , , , , ) = _pool.globalState();
  }

  function priceX96FromSqrtPriceX96(
    uint160 sqrtPriceX96
  ) public pure override returns (uint256 priceX96) {
    return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
  }

  function _adjustedPriceX96(
    IAlgebraKimV3Pool _pool,
    address _numeratorToken
  ) internal view returns (uint256) {
    address _token1 = _pool.token1();
    uint8 _decimals0 = IERC20Metadata(_pool.token0()).decimals();
    uint8 _decimals1 = IERC20Metadata(_token1).decimals();
    uint160 _sqrtPriceX96 = sqrtPriceX96FromPoolAndInterval(address(_pool));
    uint256 _priceX96 = priceX96FromSqrtPriceX96(_sqrtPriceX96);
    uint256 _ratioPriceX96 = _token1 == _numeratorToken
      ? _priceX96
      : FixedPoint96.Q96 ** 2 / _priceX96;
    return
      _token1 == _numeratorToken
        ? (_ratioPriceX96 * 10 ** _decimals0) / 10 ** _decimals1
        : (_ratioPriceX96 * 10 ** _decimals1) / 10 ** _decimals0;
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../../../contracts/interfaces/ICurvePool.sol";
import "../../../contracts/interfaces/IDecentralizedIndex.sol";
import "../../../contracts/interfaces/IDexAdapter.sol";
import "../../../contracts/interfaces/IUniswapV2Pair.sol";
import "../../../contracts/interfaces/IUniswapV3Pool.sol";
import "../../../contracts/interfaces/IV3TwapUtilities.sol";
import "../../../contracts/interfaces/IWETH.sol";
import "../../../contracts/interfaces/IZapper.sol";

contract MockZapper is IZapper, Context, Ownable {
    using SafeERC20 for IERC20;

    address constant STYETH = 0x583019fF0f430721aDa9cfb4fac8F06cA104d0B4;
    address constant YETH = 0x1BED97CBC3c24A4fb5C069C6E311a967386131f7;
    address constant WETH_YETH_POOL = 0x69ACcb968B19a53790f43e57558F5E443A91aF22;
    address V3_ROUTER;
    address immutable V2_ROUTER;
    address immutable WETH;
    IV3TwapUtilities immutable V3_TWAP_UTILS;
    IDexAdapter immutable DEX_ADAPTER;

    uint256 _slippage = 30; // 3%

    address public OHM = 0x64aa3364F17a4D01c6f1751Fd97C2BD3D7e7f1D5;
    address public pOHM;

    // token in => token out => swap pool(s)
    mapping(address => mapping(address => Pools)) public zapMap;
    // curve pool => token => idx
    mapping(address => mapping(address => int128)) public curveTokenIdx;

    event Message(string a);

    constructor(IV3TwapUtilities _v3TwapUtilities, IDexAdapter _dexAdapter, address _V3_ROUTER) Ownable(_msgSender()) {
        V2_ROUTER = _dexAdapter.V2_ROUTER();
        V3_TWAP_UTILS = _v3TwapUtilities;
        DEX_ADAPTER = _dexAdapter;
        WETH = _dexAdapter.WETH();
        V3_ROUTER = _V3_ROUTER;

        emit Message("Here");

        // if (block.chainid == 1) {
        //   // WETH/YETH
        //   _setZapMapFromPoolSingle(
        //     PoolType.CURVE,
        //     0x69ACcb968B19a53790f43e57558F5E443A91aF22
        //   );
        //   // WETH/DAI
        //   _setZapMapFromPoolSingle(
        //     PoolType.V3,
        //     0x60594a405d53811d3BC4766596EFD80fd545A270
        //   );
        //   // WETH/USDC
        //   _setZapMapFromPoolSingle(
        //     PoolType.V3,
        //     0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640
        //   );
        //   // WETH/OHM
        //   _setZapMapFromPoolSingle(
        //     PoolType.V3,
        //     0x88051B0eea095007D3bEf21aB287Be961f3d8598
        //   );
        //   // USDC/OHM
        //   _setZapMapFromPoolSingle(
        //     PoolType.V3,
        //     0x893f503FaC2Ee1e5B78665db23F9c94017Aae97D
        //   );
        // }
    }

    function _zap(address _in, address _out, uint256 _amountIn, uint256 _amountOutMin)
        internal
        returns (uint256 _amountOut)
    {
        if (_in == address(0)) {
            _amountIn = _ethToWETH(_amountIn);
            _in = WETH;
            if (_out == WETH) {
                return _amountIn;
            }
        }
        // handle pOHM separately through pod, modularize later
        bool _isOutPOHM;
        if (pOHM == _out) {
            _isOutPOHM = true;
            _out = OHM;
        }
        // handle yETH and st-yETH special through curve pool, modularize later
        if (_out == YETH || _out == STYETH) {
            require(_in == WETH, "YETHIN");
            return _wethToYeth(_amountIn, _amountOutMin, _out == STYETH);
        } else if (_in == YETH || _in == STYETH) {
            require(_out == WETH, "YETHOUT");
            return _styethToWeth(_amountIn, _amountOutMin, _in == YETH);
        }
        Pools memory _poolInfo = zapMap[_in][_out];
        // no pool so just try to swap over one path univ2
        if (_poolInfo.pool1 == address(0)) {
            address[] memory _path = new address[](2);
            _path[0] = _in;
            _path[1] = _out;
            _amountOut = _swapV2(_path, _amountIn, _amountOutMin);
        } else {
            bool _twoHops = _poolInfo.pool2 != address(0);
            if (_poolInfo.poolType == PoolType.CURVE) {
                // curve
                _amountOut = _swapCurve(
                    _poolInfo.pool1,
                    curveTokenIdx[_poolInfo.pool1][_in],
                    curveTokenIdx[_poolInfo.pool1][_out],
                    _amountIn,
                    _amountOutMin
                );
            } else if (_poolInfo.poolType == PoolType.V2) {
                // univ2
                address _token0 = IUniswapV2Pair(_poolInfo.pool1).token0();
                address[] memory _path = new address[](_twoHops ? 3 : 2);
                _path[0] = _in;
                _path[1] = !_twoHops ? _out : _token0 == _in ? IUniswapV2Pair(_poolInfo.pool1).token1() : _token0;
                if (_twoHops) {
                    _path[2] = _out;
                }
                _amountOut = _swapV2(_path, _amountIn, _amountOutMin);
            } else {
                // univ3
                if (_twoHops) {
                    address _t0 = IUniswapV3Pool(_poolInfo.pool1).token0();
                    _amountOut = _swapV3Multi(
                        _in,
                        _getPoolFee(_poolInfo.pool1),
                        _t0 == _in ? IUniswapV3Pool(_poolInfo.pool1).token1() : _t0,
                        _getPoolFee(_poolInfo.pool2),
                        _out,
                        _amountIn,
                        _amountOutMin
                    );
                } else {
                    _amountOut = _swapV3Single(_in, _getPoolFee(_poolInfo.pool1), _out, _amountIn, _amountOutMin);
                }
            }
        }
        if (!_isOutPOHM) {
            return _amountOut;
        }
        uint256 _pOHMBefore = IERC20(pOHM).balanceOf(address(this));
        IERC20(OHM).safeIncreaseAllowance(pOHM, _amountOut);
        IDecentralizedIndex(pOHM).bond(OHM, _amountOut, 0);
        return IERC20(pOHM).balanceOf(address(this)) - _pOHMBefore;
    }

    function _getPoolFee(address _pool) internal view returns (uint24) {
        return block.chainid == 42161 ? 0 : IUniswapV3Pool(_pool).fee();
    }

    function _ethToWETH(uint256 _amountETH) internal returns (uint256) {
        uint256 _wethBal = IERC20(WETH).balanceOf(address(this));
        IWETH(WETH).deposit{value: _amountETH}();
        return IERC20(WETH).balanceOf(address(this)) - _wethBal;
    }

    function _swapV3Single(address _in, uint24 _fee, address _out, uint256 _amountIn, uint256 _amountOutMin)
        internal
        returns (uint256)
    {
        if (_amountOutMin == 0) {
            address _v3Pool;
            try DEX_ADAPTER.getV3Pool(_in, _out, uint24(10000)) returns (address __v3Pool) {
                _v3Pool = __v3Pool;
            } catch {
                _v3Pool = DEX_ADAPTER.getV3Pool(_in, _out, int24(200));
            }
            address _token0 = _in < _out ? _in : _out;
            uint256 _poolPriceX96 =
                V3_TWAP_UTILS.priceX96FromSqrtPriceX96(V3_TWAP_UTILS.sqrtPriceX96FromPoolAndInterval(_v3Pool));
            _amountOutMin = _in == _token0
                ? (_poolPriceX96 * _amountIn) / FixedPoint96.Q96
                : (_amountIn * FixedPoint96.Q96) / _poolPriceX96;
        }

        uint256 _outBefore = IERC20(_out).balanceOf(address(this));
        IERC20(_in).safeIncreaseAllowance(address(DEX_ADAPTER), _amountIn);
        DEX_ADAPTER.swapV3Single(_in, _out, _fee, _amountIn, (_amountOutMin * (1000 - _slippage)) / 1000, address(this));
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

    function _swapV2(address[] memory _path, uint256 _amountIn, uint256 _amountOutMin) internal returns (uint256) {
        address _out = _path.length == 3 ? _path[2] : _path[1];
        uint256 _outBefore = IERC20(_out).balanceOf(address(this));
        IERC20(_path[0]).safeIncreaseAllowance(address(DEX_ADAPTER), _amountIn);
        DEX_ADAPTER.swapV2Single(_path[0], _path[1], _amountIn, _amountOutMin, address(this));
        return IERC20(_out).balanceOf(address(this)) - _outBefore;
    }

    function _swapCurve(address _pool, int128 _i, int128 _j, uint256 _amountIn, uint256 _amountOutMin)
        internal
        returns (uint256)
    {
        IERC20(ICurvePool(_pool).coins(uint128(_i))).safeIncreaseAllowance(_pool, _amountIn);
        return ICurvePool(_pool).exchange(_i, _j, _amountIn, _amountOutMin, address(this));
    }

    function _wethToYeth(uint256 _ethAmount, uint256 _minYethAmount, bool _stakeToStyeth) internal returns (uint256) {
        uint256 _boughtYeth = _swapCurve(WETH_YETH_POOL, 0, 1, _ethAmount, _minYethAmount);
        if (_stakeToStyeth) {
            IERC20(YETH).safeIncreaseAllowance(STYETH, _boughtYeth);
            return IERC4626(STYETH).deposit(_boughtYeth, address(this));
        }
        return _boughtYeth;
    }

    function _styethToWeth(uint256 _stYethAmount, uint256 _minWethAmount, bool _isYethOnly)
        internal
        returns (uint256)
    {
        uint256 _yethAmount;
        if (_isYethOnly) {
            _yethAmount = _stYethAmount;
        } else {
            _yethAmount = IERC4626(STYETH).redeem(_stYethAmount, address(this), address(this));
        }
        return _swapCurve(WETH_YETH_POOL, 1, 0, _yethAmount, _minWethAmount);
    }

    function _setZapMapFromPoolSingle(PoolType _type, address _pool) internal {
        address _t0;
        address _t1;
        if (_type == PoolType.CURVE) {
            _t0 = ICurvePool(_pool).coins(0);
            _t1 = ICurvePool(_pool).coins(1);
            curveTokenIdx[_pool][_t0] = 0;
            curveTokenIdx[_pool][_t1] = 1;
        } else {
            _t0 = IUniswapV3Pool(_pool).token0();
            _t1 = IUniswapV3Pool(_pool).token1();
        }
        Pools memory _poolConf = Pools({poolType: _type, pool1: _pool, pool2: address(0)});
        zapMap[_t0][_t1] = _poolConf;
        zapMap[_t1][_t0] = _poolConf;
    }

    function setOHM(address _OHM, address _pOHM) external onlyOwner {
        OHM = _OHM == address(0) ? OHM : _OHM;
        pOHM = _pOHM == address(0) ? pOHM : _pOHM;
    }

    function setSlippage(uint256 _slip) external onlyOwner {
        require(_slip >= 0 && _slip <= 1000, "BOUNDS");
        _slippage = _slip;
    }

    function setZapMap(address _in, address _out, Pools memory _pools) external onlyOwner {
        zapMap[_in][_out] = _pools;
    }

    function setZapMapFromPoolSingle(PoolType _type, address _pool) external onlyOwner {
        _setZapMapFromPoolSingle(_type, _pool);
    }

    function rescueETH() external onlyOwner {
        (bool _sent,) = payable(owner()).call{value: address(this).balance}("");
        require(_sent);
    }

    function rescueERC20(IERC20 _token) external onlyOwner {
        require(_token.balanceOf(address(this)) > 0);
        _token.safeTransfer(owner(), _token.balanceOf(address(this)));
    }

    receive() external payable {}
}

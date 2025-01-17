// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "../interfaces/IDecentralizedIndex.sol";
import "../interfaces/IStakingPoolToken.sol";
import "../interfaces/IUniswapV3Pool.sol";
import "../interfaces/ICamelotPair.sol";
import "../interfaces/IV3TwapUtilities.sol";
import "../interfaces/IV2Reserves.sol";
import "./ConversionFactorPTKN.sol";

contract ConversionFactorSPTKN is ConversionFactorPTKN {
    address immutable PEAS;
    address immutable PEAS_STABLE_CL_POOL;
    IV3TwapUtilities immutable TWAP_UTILS;
    IV2Reserves immutable V2_RESERVES;

    constructor(address _peas, address _peasStablePool, IV3TwapUtilities _utils, IV2Reserves _v2Res) {
        PEAS = _peas;
        PEAS_STABLE_CL_POOL = _peasStablePool;
        TWAP_UTILS = _utils;
        V2_RESERVES = _v2Res;
    }

    /// @notice several assumptions here, that pairedLpToken is a stable, and that any stable
    /// that may be paired are priced the same.
    function getConversionFactor(address _spTKN)
        external
        view
        override
        returns (uint256 _factor, uint256 _denomenator)
    {
        (uint256 _pFactor, uint256 _pDenomenator) = _calculateCbrWithDen(IStakingPoolToken(_spTKN).INDEX_FUND());
        address _lpTkn = IStakingPoolToken(_spTKN).stakingToken();
        address _token1 = IUniswapV3Pool(PEAS_STABLE_CL_POOL).token1();
        uint160 _sqrtPriceX96 = TWAP_UTILS.sqrtPriceX96FromPoolAndInterval(PEAS_STABLE_CL_POOL);
        uint256 _priceX96 = TWAP_UTILS.priceX96FromSqrtPriceX96(_sqrtPriceX96);
        uint256 _pricePeasNumX96 = _token1 == PEAS ? _priceX96 : FixedPoint96.Q96 ** 2 / _priceX96;
        uint256 _pricePPeasNumX96 = (_pricePeasNumX96 * _pFactor) / _pDenomenator;
        (uint112 _reserve0, uint112 _reserve1) = V2_RESERVES.getReserves(_lpTkn);
        uint256 _k = uint256(_reserve0) * _reserve1;
        uint256 _avgTotalPeasInLpX96 = _sqrt(_pricePPeasNumX96 * _k) * 2 ** (96 / 2);

        _factor = (_avgTotalPeasInLpX96 * 2) / IERC20(_lpTkn).totalSupply();
        _denomenator = FixedPoint96.Q96;
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}

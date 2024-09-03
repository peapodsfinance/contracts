// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from 'forge-std/Test.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '../../contracts/oracle/ChainlinkSinglePriceOracle.sol';
import '../../contracts/oracle/UniswapV3SinglePriceOracle.sol';
import '../../contracts/oracle/V2ReservesUniswap.sol';
import { spTKNMinimalOracle } from '../../contracts/oracle/spTKNMinimalOracle.sol';
import '../../contracts/interfaces/IStakingPoolToken.sol';
import 'forge-std/console.sol';

contract spTKNMinimalOracleTest is Test {
  V2ReservesUniswap _v2Res;
  ChainlinkSinglePriceOracle _clOracle;
  UniswapV3SinglePriceOracle _uniOracle;

  function setUp() public {
    _v2Res = new V2ReservesUniswap();
    _clOracle = new ChainlinkSinglePriceOracle();
    _uniOracle = new UniswapV3SinglePriceOracle();
  }

  function test_getPrices_PEASDAI() public {
    spTKNMinimalOracle oraclePEASDAI = new spTKNMinimalOracle(
      0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
      false,
      0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1, // spPDAI
      0xAe750560b09aD1F5246f3b279b3767AfD1D79160, // UniV3: PEAS / DAI
      0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9, // CL: DAI / USD
      address(0),
      address(0),
      address(0),
      address(_clOracle),
      address(_uniOracle),
      address(_v2Res)
    );
    (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) = oraclePEASDAI
      .getPrices();
    console.log('prices: %s -- %s', _priceLow, _priceHigh);

    uint256 _unsafePrice18 = _getUnsafeSpTknPrice18(address(oraclePEASDAI));
    console.log('unsafePrice %s - priceLow %s', _unsafePrice18, _priceLow);

    // NOTE: assumes BASE_TOKEN and UNI_V2 tokens have same decimals
    assertApproxEqAbs(
      _priceLow,
      _unsafePrice18,
      1e18 // TODO: better validate
    );
    // accounting for unwrap fee makes oracle price a bit higher
    assertEq(_priceLow > _unsafePrice18, true);
    assertEq(_isBadData, false);
  }

  function test_getPrices_NPCPEAS() public {
    spTKNMinimalOracle oracleNPCPEAS = new spTKNMinimalOracle(
      0x02f92800F57BCD74066F5709F1Daa1A4302Df875, // PEAS
      false,
      0x2683e7A6C577514C6907c09Ba13817C36e774DE9, // spNPC
      0xeB7AbE950985709c34af514eB8cf72f62DEF9E75, // UniV3: NPC / WETH
      address(0),
      0x44C95bf226A6A1385beacED2bb3328D6aFb044a3, // UniV3: PEAS / WETH
      address(0),
      address(0),
      address(_clOracle),
      address(_uniOracle),
      address(_v2Res)
    );
    (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) = oracleNPCPEAS
      .getPrices();
    console.log('prices: %s -- %s', _priceLow, _priceHigh);

    uint256 _unsafePrice18 = _getUnsafeSpTknPrice18(address(oracleNPCPEAS));
    console.log('unsafePrice %s - priceLow %s', _unsafePrice18, _priceLow);

    // NOTE: assumes BASE_TOKEN and UNI_V2 tokens have same decimals
    assertApproxEqAbs(
      _priceLow,
      _unsafePrice18,
      1e18 // TODO: better validate
    );
    // accounting for unwrap fee makes oracle price a bit more
    assertEq(_priceLow > _unsafePrice18, true);
    assertEq(_isBadData, false);
  }

  function test_getPrices_APEPOHM() public {
    spTKNMinimalOracle oracleAPEPOHM = new spTKNMinimalOracle(
      0x88E08adB69f2618adF1A3FF6CC43c671612D1ca4, // pOHM
      true,
      0x21D13197D2eABA3B47973f8e1F3f46CC96336b0E, // spAPE
      0xAc4b3DacB91461209Ae9d41EC517c2B9Cb1B7DAF, // UniV3: APE / WETH
      address(0),
      0x88051B0eea095007D3bEf21aB287Be961f3d8598, // UniV3: OHM / WETH
      address(0),
      address(0),
      address(_clOracle),
      address(_uniOracle),
      address(_v2Res)
    );
    (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) = oracleAPEPOHM
      .getPrices();
    console.log('prices: %s -- %s', _priceLow, _priceHigh);

    uint256 _unsafePrice18 = _getUnsafeSpTknPrice18(address(oracleAPEPOHM));
    console.log('unsafePrice %s - priceLow %s', _unsafePrice18, _priceLow);

    // NOTE: assumes BASE_TOKEN and UNI_V2 tokens have same decimals
    assertApproxEqAbs(
      _priceLow,
      _unsafePrice18,
      1e18 // TODO: better validate
    );
    // accounting for unwrap fee makes oracle price a bit more
    assertEq(_priceLow > _unsafePrice18, true);
    assertEq(_isBadData, false);
  }

  function _getUnsafeSpTknPrice18(
    address _oracle
  ) internal view returns (uint256 _unsafePrice18) {
    address _uniPair = IStakingPoolToken(spTKNMinimalOracle(_oracle).SP_TKN())
      .stakingToken();
    uint256 _baseAmt = IERC20(spTKNMinimalOracle(_oracle).BASE_TOKEN())
      .balanceOf(_uniPair);
    uint256 _uniSupply = IERC20(_uniPair).totalSupply();
    _unsafePrice18 = (10 ** 18 * _uniSupply) / (_baseAmt * 2);
  }
}

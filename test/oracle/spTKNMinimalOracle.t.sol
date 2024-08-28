// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from 'forge-std/Test.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '../../contracts/oracle/ChainlinkSinglePriceOracle.sol';
import '../../contracts/oracle/UniswapV3SinglePriceOracle.sol';
import { spTKNMinimalOracle } from '../../contracts/oracle/spTKNMinimalOracle.sol';
import '../../contracts/interfaces/IStakingPoolToken.sol';
import 'forge-std/console.sol';

contract spTKNMinimalOracleTest is Test {
  spTKNMinimalOracle public oraclePEASDAI;
  spTKNMinimalOracle public oracleNPCPEAS;

  function setUp() public {
    ChainlinkSinglePriceOracle _clOracle = new ChainlinkSinglePriceOracle();
    UniswapV3SinglePriceOracle _uniOracle = new UniswapV3SinglePriceOracle();
    oraclePEASDAI = new spTKNMinimalOracle(
      0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
      0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1, // spPDAI
      0xAe750560b09aD1F5246f3b279b3767AfD1D79160, // PEAS / DAI
      0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9, // CL: DAI / USD
      address(0),
      address(0),
      address(0),
      address(_clOracle),
      address(_uniOracle)
    );
    oracleNPCPEAS = new spTKNMinimalOracle(
      0x02f92800F57BCD74066F5709F1Daa1A4302Df875, // PEAS
      0x2683e7A6C577514C6907c09Ba13817C36e774DE9, // spNPC
      0xeB7AbE950985709c34af514eB8cf72f62DEF9E75, // NPC / WETH
      address(0),
      0x44C95bf226A6A1385beacED2bb3328D6aFb044a3, // PEAS / WETH
      address(0),
      address(0),
      address(_clOracle),
      address(_uniOracle)
    );
  }

  function test_getPrices_PEASDAI() public view {
    (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) = oraclePEASDAI
      .getPrices();
    console.log('prices: %s -- %s', _priceLow, _priceHigh);

    address _uniPair = IStakingPoolToken(oraclePEASDAI.SP_TKN()).stakingToken();
    uint256 _baseAmt = IERC20(oraclePEASDAI.BASE_TOKEN()).balanceOf(_uniPair);
    uint256 _uniSupply = IERC20(_uniPair).totalSupply();
    console.log(
      'directUnsafePrice %s - priceLow %s',
      (10 ** 18 * _baseAmt * 2) / _uniSupply,
      _priceLow
    );

    // NOTE: assumes BASE_TOKEN and UNI_V2 tokens have same decimals
    assertApproxEqAbs(
      _priceLow,
      (10 ** 18 * _baseAmt * 2) / _uniSupply,
      1e18 // TODO: better validate
    );
    assertEq(_isBadData, false);
  }

  function test_getPrices_NPCPEAS() public view {
    (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) = oracleNPCPEAS
      .getPrices();
    console.log('prices: %s -- %s', _priceLow, _priceHigh);

    address _uniPair = IStakingPoolToken(oracleNPCPEAS.SP_TKN()).stakingToken();
    uint256 _baseAmt = IERC20(oracleNPCPEAS.BASE_TOKEN()).balanceOf(_uniPair);
    uint256 _uniSupply = IERC20(_uniPair).totalSupply();
    console.log(
      'directUnsafePrice %s - priceLow %s',
      (10 ** 18 * _baseAmt * 2) / _uniSupply,
      _priceLow
    );

    // NOTE: assumes BASE_TOKEN and UNI_V2 tokens have same decimals
    assertApproxEqAbs(
      _priceLow,
      (10 ** 18 * _baseAmt * 2) / _uniSupply,
      1e18 // TODO: better validate
    );
    assertEq(_isBadData, false);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from 'forge-std/Test.sol';
import '@openzeppelin/contracts/interfaces/IERC20.sol';
import '../../contracts/oracle/ChainlinkSinglePriceOracle.sol';
import '../../contracts/oracle/UniswapV3SinglePriceOracle.sol';
import '../../contracts/oracle/V2ReservesUniswap.sol';
import { spTKNMinimalOracle } from '../../contracts/oracle/spTKNMinimalOracle.sol';
import '../../contracts/interfaces/IDecentralizedIndex.sol';
import '../../contracts/interfaces/IDexAdapter.sol';
import '../../contracts/interfaces/IStakingPoolToken.sol';
import '../../contracts/interfaces/IV3TwapUtilities.sol';
import { IndexUtils } from '../../contracts/IndexUtils.sol';
import { WeightedIndex } from '../../contracts/WeightedIndex.sol';
import 'forge-std/console.sol';

contract spTKNMinimalOracleTest is Test {
  V2ReservesUniswap _v2Res;
  ChainlinkSinglePriceOracle _clOracle;
  UniswapV3SinglePriceOracle _uniOracle;

  function setUp() public {
    _v2Res = new V2ReservesUniswap();
    _clOracle = new ChainlinkSinglePriceOracle(address(0));
    _uniOracle = new UniswapV3SinglePriceOracle(address(0));
  }

  function test_getPrices_PEASDAI() public {
    address _podToDup = IStakingPoolToken(
      0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1 // spPDAI
    ).indexFund();
    address _newPod = _dupPodAndSeedLp(_podToDup, address(0), 0);
    spTKNMinimalOracle oraclePEASDAI = new spTKNMinimalOracle(
      0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
      false,
      IDecentralizedIndex(_newPod).lpStakingPool(),
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

    assertApproxEqAbs(
      _priceLow,
      _unsafePrice18,
      1e18 // TODO: tighten this up
    );
    // accounting for unwrap fee makes oracle price a bit higher
    // assertGt(_priceLow, _unsafePrice18); // TODO
    assertEq(_isBadData, false, 'Bad data was passed');
  }

  function test_getPrices_NPCPEAS() public {
    address _podToDup = IStakingPoolToken(
      0x2683e7A6C577514C6907c09Ba13817C36e774DE9 // spNPC
    ).indexFund();
    address _newPod = _dupPodAndSeedLp(_podToDup, address(0), 0);
    spTKNMinimalOracle oracleNPCPEAS = new spTKNMinimalOracle(
      0x02f92800F57BCD74066F5709F1Daa1A4302Df875, // PEAS
      false,
      IDecentralizedIndex(_newPod).lpStakingPool(),
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

    assertApproxEqAbs(
      _priceLow,
      _unsafePrice18,
      1e18, // TODO: tighten this up
      'priceLow is not appoximately equal to unsafe price'
    );
    // accounting for unwrap fee makes oracle price a bit more
    // assertGt(
    //   _priceLow,
    //   _unsafePrice18,
    //   'Price low is not greater than unsafe price'
    // );
    assertEq(_isBadData, false, 'Bad data was passed');
  }

  function test_getPrices_APEPOHM() public {
    address _podToDup = IStakingPoolToken(
      0x21D13197D2eABA3B47973f8e1F3f46CC96336b0E // spAPE
    ).indexFund();
    address _newpOHM = _dupPodAndSeedLp(
      0x88E08adB69f2618adF1A3FF6CC43c671612D1ca4,
      address(0),
      0
    );
    address _newPod = _dupPodAndSeedLp(_podToDup, _newpOHM, 0);
    spTKNMinimalOracle oracleAPEPOHM = new spTKNMinimalOracle(
      _newpOHM,
      true,
      IDecentralizedIndex(_newPod).lpStakingPool(),
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

    assertApproxEqAbs(
      _priceLow,
      _unsafePrice18,
      1e18 // TODO: tighten this up
    );
    // accounting for unwrap fee makes oracle price a bit more
    // assertEq(_priceLow > _unsafePrice18, true); // TODO: check and confirm
    assertEq(_isBadData, false, 'Bad data was passed');
  }

  function test_getPrices_BTCUSDC() public {
    address _usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address _podToDup = IStakingPoolToken(
      0x65905866Fd95061c06C065856560e56c87459886 // spWBTC (pWBTC/pOHM)
    ).indexFund();
    address _newPod = _dupPodAndSeedLp(_podToDup, _usdc, 17);
    spTKNMinimalOracle oracleBTCUSDC = new spTKNMinimalOracle(
      _usdc,
      false,
      IDecentralizedIndex(_newPod).lpStakingPool(),
      0x99ac8cA7087fA4A2A1FB6357269965A2014ABc35, // UniV3: BTC / USDC
      0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6, // CL: USDC / USD
      address(0),
      0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6, // CL: USDC / USD
      0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // CL: BTC / USD
      address(_clOracle),
      address(_uniOracle),
      address(_v2Res)
    );
    (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) = oracleBTCUSDC
      .getPrices();
    console.log('prices: %s -- %s', _priceLow, _priceHigh);

    uint256 _unsafePrice18 = _getUnsafeSpTknPrice18(address(oracleBTCUSDC));
    console.log('unsafePrice %s - priceLow %s', _unsafePrice18, _priceLow);

    assertApproxEqRel(
      _priceLow,
      _unsafePrice18,
      0.1e18 // TODO: tighten this up
    );
    // accounting for unwrap fee makes oracle price a bit more
    // assertEq(_priceLow > _unsafePrice18, true); // TODO: check and confirm
    assertEq(_isBadData, false, 'Bad data was passed');
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

  function _dupPodAndSeedLp(
    address _pod,
    address _pairedOverride,
    uint256 _pairedOverrideFactorMult
  ) internal returns (address _newPod) {
    address pairedLpToken = _pairedOverride != address(0)
      ? _pairedOverride
      : IDecentralizedIndex(_pod).PAIRED_LP_TOKEN();

    IndexUtils _utils = new IndexUtils(
      IV3TwapUtilities(0x024ff47D552cB222b265D68C7aeB26E586D5229D),
      IDexAdapter(0x7686aa8B32AA9Eb135AC15a549ccd71976c878Bb)
    );

    address _underlying;
    (_underlying, _newPod) = _createPod(
      _pod,
      pairedLpToken,
      0x7686aa8B32AA9Eb135AC15a549ccd71976c878Bb
    );

    address _lpStakingPool = IDecentralizedIndex(_pod).lpStakingPool();
    address _podV2Pool = IStakingPoolToken(_lpStakingPool).stakingToken();
    deal(
      _underlying,
      address(this),
      (IERC20(_pod).balanceOf(_podV2Pool) *
        10 ** IERC20Metadata(_underlying).decimals()) /
        10 ** IERC20Metadata(_pod).decimals()
    );
    deal(
      pairedLpToken,
      address(this),
      ((_pairedOverrideFactorMult == 0 ? 1 : _pairedOverrideFactorMult) *
        (IERC20(IDecentralizedIndex(_pod).PAIRED_LP_TOKEN()).balanceOf(
          _podV2Pool
        ) * 10 ** IERC20Metadata(pairedLpToken).decimals())) /
        10 **
          IERC20Metadata(IDecentralizedIndex(_pod).PAIRED_LP_TOKEN()).decimals()
    );

    IERC20(_underlying).approve(
      _newPod,
      IERC20(_underlying).balanceOf(address(this))
    );
    IDecentralizedIndex(_newPod).bond(
      _underlying,
      IERC20(_underlying).balanceOf(address(this)),
      0
    );

    IERC20(_newPod).approve(
      address(_utils),
      IERC20(_newPod).balanceOf(address(this))
    );
    IERC20(pairedLpToken).approve(
      address(_utils),
      IERC20(pairedLpToken).balanceOf(address(this))
    );
    _utils.addLPAndStake(
      IDecentralizedIndex(_newPod),
      IERC20(_newPod).balanceOf(address(this)),
      pairedLpToken,
      IERC20(pairedLpToken).balanceOf(address(this)),
      0,
      1000,
      block.timestamp
    );
  }

  function _createPod(
    address _oldPod,
    address _pairedLpToken,
    address _dexAdapter
  ) internal returns (address _underlying, address _newPod) {
    IDecentralizedIndex.IndexAssetInfo[] memory _assets = IDecentralizedIndex(
      _oldPod
    ).getAllAssets();
    _underlying = _assets[0].token;
    IDecentralizedIndex.Config memory _c;
    _c.partner = IDecentralizedIndex(_oldPod).partner();
    IDecentralizedIndex.Fees memory _f = _getPodFees(_oldPod);
    address[] memory _t = new address[](1);
    _t[0] = address(_underlying);
    uint256[] memory _w = new uint256[](1);
    _w[0] = 100;
    _newPod = address(
      new WeightedIndex(
        'Test',
        'pTEST',
        _c,
        _f,
        _t,
        _w,
        _pairedLpToken,
        0x02f92800F57BCD74066F5709F1Daa1A4302Df875,
        false,
        _getImmutables(_dexAdapter)
      )
    );
  }

  function _getImmutables(
    address _dexAdapter
  ) internal pure returns (bytes memory) {
    return
      abi.encode(
        0x6B175474E89094C44Da98b954EedeAC495271d0F,
        0x7d544DD34ABbE24C8832db27820Ff53C151e949b,
        0xEc0Eb48d2D638f241c1a7F109e38ef2901E9450F,
        0x024ff47D552cB222b265D68C7aeB26E586D5229D,
        _dexAdapter
      );
  }

  function _getPodFees(
    address _pod
  ) internal view returns (IDecentralizedIndex.Fees memory _f) {
    (
      uint16 _f0,
      uint16 _f1,
      uint16 _f2,
      uint16 _f3,
      uint16 _f4,
      uint16 _f5
    ) = WeightedIndex(payable(_pod)).fees();
    _f.burn = _f0;
    _f.bond = _f1;
    _f.debond = _f2;
    _f.buy = _f3;
    _f.sell = _f4;
    _f.partner = _f5;
  }
}

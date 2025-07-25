// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/console.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../../contracts/oracle/ChainlinkSinglePriceOracle.sol";
import "../../contracts/oracle/UniswapV3SinglePriceOracle.sol";
import {DIAOracleV2SinglePriceOracle} from "../../contracts/oracle/DIAOracleV2SinglePriceOracle.sol";
import "../../contracts/oracle/V2ReservesUniswap.sol";
import {spTKNMinimalOracle} from "../../contracts/oracle/spTKNMinimalOracle.sol";
import "../../contracts/interfaces/IDecentralizedIndex.sol";
import "../../contracts/interfaces/IStakingPoolToken.sol";
import {MockChainlinkStaleData} from "../mocks/MockChainlinkStaleData.sol";
import {MockDIAOracleV2} from "../mocks/MockDIAOracleV2.sol";
import {PodHelperTest} from "../helpers/PodHelper.t.sol";

interface IStakingPoolToken_OLD {
    function indexFund() external view returns (address);
}

contract spTKNMinimalOracleTest is PodHelperTest {
    V2ReservesUniswap _v2Res;
    ChainlinkSinglePriceOracle _clOracle;
    UniswapV3SinglePriceOracle _uniOracle;
    DIAOracleV2SinglePriceOracle _diaOracle;

    function setUp() public override {
        _v2Res = new V2ReservesUniswap();
        _clOracle = new ChainlinkSinglePriceOracle(address(0));
        _uniOracle = new UniswapV3SinglePriceOracle(address(0));
        _diaOracle = new DIAOracleV2SinglePriceOracle(address(0));
        super.setUp();
    }

    function test_getPrices_LowZero() public {
        address _usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address _podToDup = IStakingPoolToken_OLD(0x65905866Fd95061c06C065856560e56c87459886).indexFund(); // spWBTC (pWBTC/pOHM)
        address _newPod = _dupPodAndSeedLp(_podToDup, _usdc, 20, 0); // $20 pOHM, $1 USDC, 20/1 = 20
        address clStaleData = address(new MockChainlinkStaleData());
        spTKNMinimalOracle oracleBTCUSDC = new spTKNMinimalOracle(
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                _usdc,
                false,
                false,
                IDecentralizedIndex(_newPod).lpStakingPool(),
                0x99ac8cA7087fA4A2A1FB6357269965A2014ABc35 // UniV3: BTC / USDC
            ),
            abi.encode(
                clStaleData, // CL: USDC / USD
                address(0),
                address(0),
                0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6, // CL: USDC / USD
                0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // CL: BTC / USD
                address(0),
                address(_v2Res)
            )
        );
        vm.expectRevert();
        // (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) = oracleBTCUSDC
        //   .getPrices();
        oracleBTCUSDC.getPrices();
        // console.log('prices: %s -- %s', _priceLow, _priceHigh);

        // assertGt(_priceHigh, 0, 'Price low is not greater than 0');
        // assertEq(_priceLow, 0, 'Price low is not 0');
        // assertEq(_isBadData, true, 'Bad data was not passed');
    }

    function test_getPodPerBasePrice_PEASDAI() public {
        address _podToDup = IStakingPoolToken_OLD(0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1).indexFund(); // spPDAI
        address _newPod = _dupPodAndSeedLp(_podToDup, address(0), 0, 0);
        spTKNMinimalOracle oraclePEASDAI = new spTKNMinimalOracle(
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
                false,
                false,
                IDecentralizedIndex(_newPod).lpStakingPool(),
                0xAe750560b09aD1F5246f3b279b3767AfD1D79160 // UniV3: PEAS / DAI
            ),
            abi.encode(address(0), address(0), address(0), address(0), address(0), address(0), address(_v2Res))
        );
        uint256 _price18 = oraclePEASDAI.getPodPerBasePrice();
        assertApproxEqRel(
            _price18,
            0.33 ether, // NOTE: At the time of writing test DAI/PEAS == $3, so inverse is 1/3 == 0.33
            0.2e18 // NOTE: At the time of writing test DAI/PEAS ~= $3, so _price18 would be ~1/3 == 0.33, so precision to <= 1 here (it's wide I know)
        );
    }

    function test_getPrices_PEASDAI() public {
        address _podToDup = IStakingPoolToken_OLD(0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1).indexFund(); // spPDAI
        address _newPod = _dupPodAndSeedLp(_podToDup, address(0), 0, 0);
        spTKNMinimalOracle oraclePEASDAI = new spTKNMinimalOracle(
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
                false,
                false,
                IDecentralizedIndex(_newPod).lpStakingPool(),
                0xAe750560b09aD1F5246f3b279b3767AfD1D79160 // UniV3: PEAS / DAI
            ),
            abi.encode(address(0), address(0), address(0), address(0), address(0), address(0), address(_v2Res))
        );
        (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) = oraclePEASDAI.getPrices();

        uint256 _unsafePrice18 = _getUnsafeSpTknPrice18(address(oraclePEASDAI));
        console.log("unsafePrice %s - priceLow %s", _unsafePrice18, _priceLow);
        console.log("unsafePrice %s - priceHigh %s", _unsafePrice18, _priceHigh);

        assertApproxEqRel(
            _priceLow,
            _unsafePrice18,
            0.2e18 // TODO: tighten this up
        );
        assertApproxEqRel(
            _priceHigh,
            _unsafePrice18,
            0.2e18 // TODO: tighten this up
        );
        // accounting for unwrap fee makes oracle price a bit higher
        // assertGt(_priceLow, _unsafePrice18); // TODO
        assertEq(_isBadData, false, "Bad data was passed");
    }

    function test_getPrices_PEASDAI_DIABaseConversionOracle() public {
        MockDIAOracleV2 _peasDiaOracle = new MockDIAOracleV2();
        _peasDiaOracle.setValue("DAI/USD", 100000000, uint128(block.timestamp));

        address _podToDup = IStakingPoolToken_OLD(0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1).indexFund(); // spPDAI
        address _newPod = _dupPodAndSeedLp(_podToDup, address(0), 0, 0);
        spTKNMinimalOracle oraclePEASDAI_DIA = new spTKNMinimalOracle(
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
                false,
                false,
                IDecentralizedIndex(_newPod).lpStakingPool(),
                0xAe750560b09aD1F5246f3b279b3767AfD1D79160 // UniV3: PEAS / DAI
            ),
            abi.encode(
                address(0), address(0), address(_peasDiaOracle), address(0), address(0), address(0), address(_v2Res)
            )
        );
        (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) = oraclePEASDAI_DIA.getPrices();

        uint256 _unsafePrice18 = _getUnsafeSpTknPrice18(address(oraclePEASDAI_DIA));
        console.log("unsafePrice %s - priceLow %s", _unsafePrice18, _priceLow);
        console.log("unsafePrice %s - priceHigh %s", _unsafePrice18, _priceHigh);

        assertApproxEqRel(
            _priceLow,
            _unsafePrice18,
            0.2e18 // TODO: tighten this up
        );
        assertApproxEqRel(
            _priceHigh,
            _unsafePrice18,
            0.2e18 // TODO: tighten this up
        );
        // accounting for unwrap fee makes oracle price a bit higher
        // assertGt(_priceLow, _unsafePrice18); // TODO
        assertEq(_isBadData, false, "Bad data was passed");
    }

    function test_getPrices_PEASDAI_DIAPrimaryOracle() public {
        // setup dup PEAS/DAI pod to get price to put into DIA oracle
        address __podToDup = IStakingPoolToken_OLD(0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1).indexFund(); // spPDAI
        address __newPod = _dupPodAndSeedLp(__podToDup, address(0), 0, 0);
        spTKNMinimalOracle _oraclePEASDAI = new spTKNMinimalOracle(
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
                false,
                false,
                IDecentralizedIndex(__newPod).lpStakingPool(),
                0xAe750560b09aD1F5246f3b279b3767AfD1D79160 // UniV3: PEAS / DAI
            ),
            abi.encode(address(0), address(0), address(0), address(0), address(0), address(0), address(_v2Res))
        );
        uint256 _pTknPerDaiPrice18 = _oraclePEASDAI.getPodPerBasePrice();

        // setup DIA oracle with pod/dai price
        MockDIAOracleV2 _peasDiaOracle = new MockDIAOracleV2();
        _peasDiaOracle.setValue("PEAS/USD", uint128(10 ** (18 + 8) / _pTknPerDaiPrice18), uint128(block.timestamp)); // 8 decimal precision

        address _podToDup = IStakingPoolToken_OLD(0x4D57ad8FB14311e1Fc4b3fcaC62129506FF373b1).indexFund(); // spPDAI
        address _newPod = _dupPodAndSeedLp(_podToDup, address(0), 0, 0);
        spTKNMinimalOracle oraclePEASDAI_DIA = new spTKNMinimalOracle(
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
                false,
                false,
                IDecentralizedIndex(_newPod).lpStakingPool(),
                address(0)
            ),
            abi.encode(
                address(0), address(0), address(0), address(0), address(0), address(_peasDiaOracle), address(_v2Res)
            )
        );
        (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) = oraclePEASDAI_DIA.getPrices();

        uint256 _unsafePrice18 = _getUnsafeSpTknPrice18(address(oraclePEASDAI_DIA));
        console.log("unsafePrice %s - priceLow %s", _unsafePrice18, _priceLow);
        console.log("unsafePrice %s - priceHigh %s", _unsafePrice18, _priceHigh);

        assertApproxEqRel(
            _priceLow,
            _unsafePrice18,
            0.2e18 // TODO: tighten this up
        );
        assertApproxEqRel(
            _priceHigh,
            _unsafePrice18,
            0.2e18 // TODO: tighten this up
        );
        // accounting for unwrap fee makes oracle price a bit higher
        // assertGt(_priceLow, _unsafePrice18); // TODO
        assertEq(_isBadData, false, "Bad data was passed");
    }

    function test_getPrices_NPCPEAS() public {
        address _podToDup = IStakingPoolToken_OLD(0x2683e7A6C577514C6907c09Ba13817C36e774DE9).indexFund(); // spNPC
        address _newPod = _dupPodAndSeedLp(_podToDup, address(0), 0, 0);
        spTKNMinimalOracle oracleNPCPEAS = new spTKNMinimalOracle(
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                0x02f92800F57BCD74066F5709F1Daa1A4302Df875, // PEAS
                false,
                false,
                IDecentralizedIndex(_newPod).lpStakingPool(),
                0xeB7AbE950985709c34af514eB8cf72f62DEF9E75 // UniV3: NPC / WETH
            ),
            abi.encode(
                address(0),
                0x44C95bf226A6A1385beacED2bb3328D6aFb044a3, // UniV3: PEAS / WETH
                address(0),
                address(0),
                address(0),
                address(0),
                address(_v2Res)
            )
        );
        (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) = oracleNPCPEAS.getPrices();

        uint256 _unsafePrice18 = _getUnsafeSpTknPrice18(address(oracleNPCPEAS));
        console.log("unsafePrice %s - priceLow %s", _unsafePrice18, _priceLow);
        console.log("unsafePrice %s - priceHigh %s", _unsafePrice18, _priceHigh);

        assertApproxEqRel(
            _priceLow,
            _unsafePrice18,
            0.2e18, // TODO: tighten this up
            "priceLow is not appoximately equal to unsafe price"
        );
        assertApproxEqRel(
            _priceHigh,
            _unsafePrice18,
            0.2e18, // TODO: tighten this up
            "_priceHigh is not appoximately equal to unsafe price"
        );
        assertEq(_isBadData, false, "Bad data was passed");
    }

    function test_getPrices_APEPOHM() public {
        address _podToDup = IStakingPoolToken_OLD(0x21D13197D2eABA3B47973f8e1F3f46CC96336b0E).indexFund(); // spAPE
        address _newpOHM = _dupPodAndSeedLp(0x88E08adB69f2618adF1A3FF6CC43c671612D1ca4, address(0), 0, 0);
        address _newPod = _dupPodAndSeedLp(_podToDup, _newpOHM, 0, 0);
        spTKNMinimalOracle oracleAPEPOHM = new spTKNMinimalOracle(
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                _newpOHM,
                true,
                false,
                IDecentralizedIndex(_newPod).lpStakingPool(),
                0xAc4b3DacB91461209Ae9d41EC517c2B9Cb1B7DAF // UniV3: APE / WETH
            ),
            abi.encode(
                address(0),
                0x88051B0eea095007D3bEf21aB287Be961f3d8598, // UniV3: OHM / WETH
                address(0),
                address(0),
                address(0),
                address(0),
                address(_v2Res)
            )
        );
        (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) = oracleAPEPOHM.getPrices();

        uint256 _unsafePrice18 = _getUnsafeSpTknPrice18(address(oracleAPEPOHM));
        console.log("unsafePrice %s - priceLow %s", _unsafePrice18, _priceLow);
        console.log("unsafePrice %s - priceHigh %s", _unsafePrice18, _priceHigh);

        assertApproxEqRel(
            _priceLow,
            _unsafePrice18,
            0.2e18, // TODO: tighten this up
            "_priceLow not close to _unsafePrice18"
        );
        assertApproxEqRel(
            _priceHigh,
            _unsafePrice18,
            0.2e18, // TODO: tighten this up
            "_priceHigh not close to _unsafePrice18"
        );
        // accounting for unwrap fee makes oracle price a bit more
        // assertEq(_priceLow > _unsafePrice18, true); // TODO: check and confirm
        assertEq(_isBadData, false, "Bad data was passed");
    }

    function test_getPrices_BTCUSDC() public {
        address _usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address _podToDup = IStakingPoolToken_OLD(0x65905866Fd95061c06C065856560e56c87459886).indexFund(); // spWBTC (pWBTC/pOHM)
        address _newPod = _dupPodAndSeedLp(_podToDup, _usdc, 20, 0); // $20 pOHM, $1 USDC, 20/1 = 20
        spTKNMinimalOracle oracleBTCUSDC = new spTKNMinimalOracle(
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                _usdc,
                false,
                false,
                IDecentralizedIndex(_newPod).lpStakingPool(),
                0x99ac8cA7087fA4A2A1FB6357269965A2014ABc35 // UniV3: WBTC / USDC
            ),
            abi.encode(
                address(0),
                address(0),
                address(0),
                0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6, // CL: USDC / USD
                0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // CL: BTC / USD
                address(0),
                address(_v2Res)
            )
        );
        (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) = oracleBTCUSDC.getPrices();

        uint256 _unsafePrice18 = _getUnsafeSpTknPrice18(address(oracleBTCUSDC));
        console.log("unsafePrice %s - priceLow %s", _unsafePrice18, _priceLow);
        console.log("unsafePrice %s - priceHigh %s", _unsafePrice18, _priceHigh);

        assertApproxEqRel(
            _priceLow,
            _unsafePrice18,
            0.1e18, // TODO: tighten this up
            "_priceLow not close to _unsafePrice18"
        );
        assertApproxEqRel(
            _priceHigh,
            _unsafePrice18,
            0.1e18, // TODO: tighten this up
            "_priceHigh not close to _unsafePrice18"
        );
        // accounting for unwrap fee makes oracle price a bit more
        // assertEq(_priceLow > _unsafePrice18, true); // TODO: check and confirm
        assertEq(_isBadData, false, "Bad data was passed");
    }

    // function test_getPrices_BTCUSDC_BadOracleInputs() public {
    //     address _usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    //     address _podToDup = IStakingPoolToken_OLD(0x65905866Fd95061c06C065856560e56c87459886).indexFund(); // spWBTC (pWBTC/pOHM)
    //     address _newPod = _dupPodAndSeedLp(_podToDup, _usdc, 20, 0); // $20 pOHM, $1 USDC, 20/1 = 20

    //     vm.expectRevert(spTKNMinimalOracle.PrimaryOracleConfigInvalid.selector);
    //     new spTKNMinimalOracle(
    //         abi.encode(
    //             address(_clOracle),
    //             address(_uniOracle),
    //             address(_diaOracle),
    //             _usdc,
    //             false,
    //             false,
    //             IDecentralizedIndex(_newPod).lpStakingPool(),
    //             address(0) // *** no UniV3 pool provided
    //         ),
    //         abi.encode(
    //             address(0),
    //             address(0),
    //             address(0),
    //             address(0), // *** no chainink base feed provided
    //             address(0), // *** no chainlink quote feed provided
    //             address(0),
    //             address(_v2Res)
    //         )
    //     );

    //     vm.expectRevert(spTKNMinimalOracle.QuoteAndBaseChainlinkFeedsNotProvided.selector);
    //     new spTKNMinimalOracle(
    //         abi.encode(
    //             address(_clOracle),
    //             address(_uniOracle),
    //             address(_diaOracle),
    //             _usdc,
    //             false,
    //             false,
    //             IDecentralizedIndex(_newPod).lpStakingPool(),
    //             address(0) // *** no UniV3 pool provided
    //         ),
    //         abi.encode(
    //             address(0),
    //             address(0),
    //             address(0),
    //             address(0), // *** no chainink base feed provided
    //             0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // CL: BTC / USD
    //             address(0),
    //             address(_v2Res)
    //         )
    //     );
    // }

    function test_getPrices_BTCUSDC_ChainlinkOnly() public {
        address _usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address _podToDup = IStakingPoolToken_OLD(0x65905866Fd95061c06C065856560e56c87459886).indexFund(); // spWBTC (pWBTC/pOHM)
        address _newPod = _dupPodAndSeedLp(_podToDup, _usdc, 20, 0); // $20 pOHM, $1 USDC, 20/1 = 20
        spTKNMinimalOracle oracleBTCUSDC = new spTKNMinimalOracle(
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                _usdc,
                false,
                false,
                IDecentralizedIndex(_newPod).lpStakingPool(),
                address(0) // *** No UniV3 pool
            ),
            abi.encode(
                address(0),
                address(0),
                address(0),
                0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6, // CL: USDC / USD
                0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // CL: BTC / USD
                address(0),
                address(_v2Res)
            )
        );
        (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) = oracleBTCUSDC.getPrices();

        uint256 _unsafePrice18 = _getUnsafeSpTknPrice18(address(oracleBTCUSDC));
        console.log("unsafePrice %s - priceLow %s", _unsafePrice18, _priceLow);
        console.log("unsafePrice %s - priceHigh %s", _unsafePrice18, _priceHigh);

        assertApproxEqRel(
            _priceLow,
            _unsafePrice18,
            0.1e18, // TODO: tighten this up
            "_priceLow not close to _unsafePrice18"
        );
        assertApproxEqRel(
            _priceHigh,
            _unsafePrice18,
            0.1e18, // TODO: tighten this up
            "_priceHigh not close to _unsafePrice18"
        );
        // accounting for unwrap fee makes oracle price a bit more
        // assertEq(_priceLow > _unsafePrice18, true); // TODO: check and confirm
        assertEq(_isBadData, false, "Bad data was passed");
    }

    function test_getPrices_BTCUSDC_BTCWETH_ClPool() public {
        address _usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address _podToDup = IStakingPoolToken_OLD(0x65905866Fd95061c06C065856560e56c87459886).indexFund(); // spWBTC (pWBTC/pOHM)
        address _newPod = _dupPodAndSeedLp(_podToDup, _usdc, 20, 0); // $20 pOHM, $1 USDC, 20/1
        spTKNMinimalOracle oracleBTCUSDC1 = new spTKNMinimalOracle(
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                _usdc,
                false,
                false,
                IDecentralizedIndex(_newPod).lpStakingPool(),
                0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0 // UniV3: WBTC / WETH
            ),
            abi.encode(
                0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, // CL: WETH / USD // address(0),
                address(0),
                address(0),
                0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6, // CL: USDC / USD
                0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // CL: BTC / USD
                address(0),
                address(_v2Res)
            )
        );
        (bool _isBadData1, uint256 _priceLow1, uint256 _priceHigh1) = oracleBTCUSDC1.getPrices();

        spTKNMinimalOracle oracleBTCUSDC2 = new spTKNMinimalOracle(
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                _usdc,
                false,
                false,
                IDecentralizedIndex(_newPod).lpStakingPool(),
                0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0 // UniV3: WBTC / WETH
            ),
            abi.encode(
                address(0),
                0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640, // UniV3: WETH / USDC
                address(0),
                0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6, // CL: USDC / USD
                0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // CL: BTC / USD
                address(0),
                address(_v2Res)
            )
        );
        (bool _isBadData2, uint256 _priceLow2, uint256 _priceHigh2) = oracleBTCUSDC2.getPrices();

        uint256 _unsafePrice18 = _getUnsafeSpTknPrice18(address(oracleBTCUSDC1));
        console.log("unsafePrice %s - priceLow1 %s", _unsafePrice18, _priceLow1);
        console.log("unsafePrice %s - priceHigh1 %s", _unsafePrice18, _priceHigh1);
        console.log("unsafePrice %s - priceLow2 %s", _unsafePrice18, _priceLow2);
        console.log("unsafePrice %s - priceHigh2 %s", _unsafePrice18, _priceHigh2);

        assertApproxEqRel(
            _priceLow1,
            _unsafePrice18,
            0.05e18, // TODO: tighten this up
            "_priceLow1 not close to _unsafePrice18"
        );
        assertApproxEqRel(
            _priceHigh1,
            _unsafePrice18,
            0.05e18, // TODO: tighten this up
            "_priceHigh1 not close to _unsafePrice18"
        );
        assertApproxEqRel(
            _priceLow2,
            _unsafePrice18,
            0.05e18, // TODO: tighten this up
            "_priceLow2 not close to _unsafePrice18"
        );
        assertApproxEqRel(
            _priceHigh2,
            _unsafePrice18,
            0.05e18, // TODO: tighten this up
            "_priceHigh2 not close to _unsafePrice18"
        );
        // accounting for unwrap fee makes oracle price a bit more
        // assertEq(_priceLow > _unsafePrice18, true); // TODO: check and confirm
        assertEq(_isBadData1, false, "BadData1 was passed");
        assertEq(_isBadData2, false, "BadData2 was passed");
    }

    function test_getPrices_BTCWETH() public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address _podToDup = IStakingPoolToken_OLD(0x65905866Fd95061c06C065856560e56c87459886).indexFund(); // spWBTC (pWBTC/pOHM)
        address _newPod = _dupPodAndSeedLp(_podToDup, weth, 0, 120); // $2400 ETH, $20 pOHM, 2400/20
        spTKNMinimalOracle oracleBTCWETH = new spTKNMinimalOracle(
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                weth,
                false,
                false,
                IDecentralizedIndex(_newPod).lpStakingPool(),
                0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0 // UniV3: WBTC / WETH
            ),
            abi.encode(
                address(0),
                address(0),
                address(0),
                0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, // CL: ETH / USD
                0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // CL: BTC / USD
                address(0),
                address(_v2Res)
            )
        );
        (bool _isBadData, uint256 _priceLow, uint256 _priceHigh) = oracleBTCWETH.getPrices();

        uint256 _unsafePrice18 = _getUnsafeSpTknPrice18(address(oracleBTCWETH));
        console.log("unsafePrice %s - priceLow %s", _unsafePrice18, _priceLow);
        console.log("unsafePrice %s - priceHigh %s", _unsafePrice18, _priceHigh);

        assertApproxEqRel(
            _priceLow,
            _unsafePrice18,
            0.05e18, // TODO: tighten this up
            "_priceLow not close to _unsafePrice18"
        );
        assertApproxEqRel(
            _priceHigh,
            _unsafePrice18,
            0.05e18, // TODO: tighten this up
            "_priceHigh not close to _unsafePrice18"
        );
        // accounting for unwrap fee makes oracle price a bit more
        // assertEq(_priceLow > _unsafePrice18, true); // TODO: check and confirm
        assertEq(_isBadData, false, "Bad data was passed");
    }

    function test_getPrices_BTCWETH_RevertIfPodLocked() public {
        address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address _podToDup = IStakingPoolToken_OLD(0x65905866Fd95061c06C065856560e56c87459886).indexFund(); // spWBTC (pWBTC/pOHM)
        address _newPod = _dupPodAndSeedLp(_podToDup, weth, 0, 120); // $2600 ETH, $22 pOHM, 2600/22 = 120

        spTKNMinimalOracle oracleBTCWETH = new spTKNMinimalOracle(
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                weth,
                false,
                false,
                IDecentralizedIndex(_newPod).lpStakingPool(),
                0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0 // UniV3: WBTC / WETH
            ),
            abi.encode(
                address(0),
                address(0),
                address(0),
                0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, // CL: ETH / USD
                0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // CL: BTC / USD
                address(0),
                address(_v2Res)
            )
        );

        // wrap into the pod for the flashMint fee
        deal(wbtc, address(this), 1e18);
        IERC20(wbtc).approve(_newPod, 1e18);
        IDecentralizedIndex(_newPod).bond(wbtc, 1e18, 0);
        vm.expectRevert(spTKNMinimalOracle.PodLocked.selector);
        IDecentralizedIndex(_newPod).flashMint(
            address(this), 1e18, abi.encode(_newPod, address(oracleBTCWETH), uint256(1e18))
        );
    }

    function test_getPrices_BTCWETH_PassesIfBaseTknFlashMinted() public {
        address wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address _podToDup = IStakingPoolToken_OLD(0x65905866Fd95061c06C065856560e56c87459886).indexFund(); // spWBTC (pWBTC/pOHM)
        address _newBasePod = _dupPodAndSeedLp(_podToDup, weth, 0, 120); // $2600 ETH, $22 pOHM, 2600/22 = 120
        address _newPod = _dupPodAndSeedLp(_podToDup, _newBasePod, 0, 120); // $2600 ETH, $22 pOHM, 2600/22 = 120

        spTKNMinimalOracle oracleBTCWETH = new spTKNMinimalOracle(
            abi.encode(
                address(_clOracle),
                address(_uniOracle),
                address(_diaOracle),
                _newBasePod,
                true,
                false,
                IDecentralizedIndex(_newPod).lpStakingPool(),
                0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0 // UniV3: WBTC / WETH
            ),
            abi.encode(
                address(0),
                address(0),
                address(0),
                0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, // CL: ETH / USD
                0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // CL: BTC / USD
                address(0),
                address(_v2Res)
            )
        );

        // wrap into the pod for the flashMint fee
        deal(wbtc, address(this), 2e18);
        IERC20(wbtc).approve(_newBasePod, 2e18);
        IDecentralizedIndex(_newBasePod).bond(wbtc, 2e18, 0);
        // should pass without revert
        IDecentralizedIndex(_newBasePod).flashMint(
            address(this), 1e18, abi.encode(_newBasePod, address(oracleBTCWETH), 1e18)
        );
    }

    // needed for flashMint test to test locked state and revert
    function callback(bytes calldata _data) external {
        (address _pod, address _oracle, uint256 _amt) = abi.decode(_data, (address, address, uint256));
        spTKNMinimalOracle(_oracle).getPrices();
        IERC20(_pod).transfer(_pod, _amt + _amt / 1000);
    }

    function _getUnsafeSpTknPrice18(address _oracle) internal view returns (uint256 _unsafePrice18) {
        address _uniPair = IStakingPoolToken(spTKNMinimalOracle(_oracle).spTkn()).stakingToken();
        uint256 _baseAmt = IERC20(spTKNMinimalOracle(_oracle).BASE_TOKEN()).balanceOf(_uniPair);
        uint256 _uniSupply = IERC20(_uniPair).totalSupply();
        _unsafePrice18 = (10 ** 18 * _uniSupply) / (_baseAmt * 2);
    }
}

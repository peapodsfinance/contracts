// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../contracts/oracle/aspTKNMinimalOracle.sol";

interface IAspTknOracleFactory {
    function create(address _aspTKN, bytes memory _requiredImmutables, bytes memory _optionalImmutables, uint96 _salt)
        external
        returns (address _oracleAddress);
}

interface IFraxPair {
    function exchangeRateInfo()
        external
        view
        returns (
            address oracle,
            uint32 maxOracleDeviation,
            uint184 lastTimestamp,
            uint256 lowExchangeRate,
            uint256 highExchangeRate
        );

    function owner() external view returns (address);

    function timelockAddress() external view returns (address);

    function acceptTransferTimelock() external;

    function transferTimelock(address _newTimelock) external;

    function setOracle(address _newOracle, uint32 _newMaxOracleDeviation) external;
}

contract GetAspTKNOracleInfo is Script {
    function run() external {
        address _lendingPair = vm.envAddress("PAIR");
        (address _oracle, uint32 _maxOracleDeviation,,,) = IFraxPair(_lendingPair).exchangeRateInfo();
        address _timelock = IFraxPair(_lendingPair).timelockAddress();

        console.log("ORACLE", _oracle);
        console.log("OWNER", IFraxPair(_lendingPair).owner());
        console.log("TIMELOCK", _timelock);
        console.log("BASE_TOKEN", aspTKNMinimalOracle(_oracle).BASE_TOKEN());
        console.log("BASE_IS_POD", aspTKNMinimalOracle(_oracle).BASE_IS_POD());
        console.log("BASE_IS_FRAX_PAIR", aspTKNMinimalOracle(_oracle).BASE_IS_FRAX_PAIR());

        console.log("UNDERLYING_TKN_CL_POOL", aspTKNMinimalOracle(_oracle).UNDERLYING_TKN_CL_POOL());

        console.log("BASE_CONVERSION_CHAINLINK_FEED", aspTKNMinimalOracle(_oracle).BASE_CONVERSION_CHAINLINK_FEED());
        console.log("BASE_CONVERSION_CL_POOL", aspTKNMinimalOracle(_oracle).BASE_CONVERSION_CL_POOL());
        console.log("BASE_CONVERSION_DIA_FEED", aspTKNMinimalOracle(_oracle).BASE_CONVERSION_DIA_FEED());

        console.log("CHAINLINK_BASE_PRICE_FEED", aspTKNMinimalOracle(_oracle).CHAINLINK_BASE_PRICE_FEED());
        console.log("CHAINLINK_QUOTE_PRICE_FEED", aspTKNMinimalOracle(_oracle).CHAINLINK_QUOTE_PRICE_FEED());

        address _diaPriceFeed;
        try aspTKNMinimalOracle(_oracle).DIA_QUOTE_PRICE_FEED() returns (address _origDiaOracle) {
            _diaPriceFeed = _origDiaOracle;
        } catch {
            console.log("** Oracle does not have DIA_QUOTE_PRICE_FEED interface");
        }
        console.log("DIA_QUOTE_PRICE_FEED", _diaPriceFeed);

        // console.log("CHAINLINK_SINGLE_PRICE_ORACLE", aspTKNMinimalOracle(_oracle).CHAINLINK_SINGLE_PRICE_ORACLE());
        // console.log("UNISWAP_V3_SINGLE_PRICE_ORACLE", aspTKNMinimalOracle(_oracle).UNISWAP_V3_SINGLE_PRICE_ORACLE());
        // console.log("DIA_SINGLE_PRICE_ORACLE", aspTKNMinimalOracle(_oracle).DIA_SINGLE_PRICE_ORACLE());

        console.log("V2_RESERVES", address(aspTKNMinimalOracle(_oracle).V2_RESERVES()));

        console.log("spTkn", aspTKNMinimalOracle(_oracle).spTkn());
        console.log("pod", aspTKNMinimalOracle(_oracle).pod());
        console.log("underlyingTkn", aspTKNMinimalOracle(_oracle).underlyingTkn());

        console.log("getPodPerBasePrice", aspTKNMinimalOracle(_oracle).getPodPerBasePrice());

        (bool _isBadData, uint256 _low, uint256 _high) = aspTKNMinimalOracle(_oracle).getPrices();
        console.log("isBadData", _isBadData);
        console.log("getPrices_low", _low);
        console.log("getPrices_high", _high);

        // if factory is present, go ahead and create a new oracle with old oracle config
        // this is useful if we deploy new oracle code
        try vm.envAddress("ASP_ORACLE_FACTORY") returns (address _aspTknOracleFactory) {
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
            vm.startBroadcast(deployerPrivateKey);

            if (_timelock != vm.addr(deployerPrivateKey)) {
                IFraxPair(_lendingPair).acceptTransferTimelock();
            }

            address _newOracle = _createNewOracle(_aspTknOracleFactory, _oracle, _diaPriceFeed);
            console.log("new aspTKNMinimalOracle", _newOracle);

            (bool _isBadDataNew, uint256 _lowNew, uint256 _highNew) = aspTKNMinimalOracle(_newOracle).getPrices();
            console.log("isBadDataNew", _isBadDataNew);
            console.log("getPrices_lowNew", _lowNew);
            console.log("getPrices_highNew", _highNew);

            // if the code of the oracle we care about is the same as we just deployed, don't
            // proceed to set in the pair since it doesn't make sense
            if (keccak256(abi.encodePacked(_oracle.code)) == keccak256(abi.encodePacked(_newOracle.code))) {
                console.log("** code of oracle matches what we would deploy locally, short circuiting");
                return;
            }

            try vm.envBool("SET_IN_PAIR") returns (bool _setInPair) {
                if (_setInPair) {
                    IFraxPair(_lendingPair).setOracle(_newOracle, _maxOracleDeviation);
                    if (_timelock != vm.addr(deployerPrivateKey)) {
                        IFraxPair(_lendingPair).transferTimelock(_timelock);
                    }
                    (address _oracleAfterSet,,,,) = IFraxPair(_lendingPair).exchangeRateInfo();
                    console.log("Successfully set new oracle in pair!", _oracleAfterSet);
                }
            } catch {
                console.log("** Not setting new oracle in pair...");
            }

            vm.stopBroadcast();
        } catch {
            console.log("** Not creating new oracle...");
        }
    }

    function _createNewOracle(address _aspTknOracleFactory, address _originalOracle, address _diaOracle)
        internal
        returns (address _newOracle)
    {
        _newOracle = IAspTknOracleFactory(_aspTknOracleFactory).create(
            aspTKNMinimalOracle(_originalOracle).ASP_TKN(),
            abi.encode(
                aspTKNMinimalOracle(_originalOracle).CHAINLINK_SINGLE_PRICE_ORACLE(),
                aspTKNMinimalOracle(_originalOracle).UNISWAP_V3_SINGLE_PRICE_ORACLE(),
                aspTKNMinimalOracle(_originalOracle).DIA_SINGLE_PRICE_ORACLE(),
                aspTKNMinimalOracle(_originalOracle).BASE_TOKEN(),
                aspTKNMinimalOracle(_originalOracle).BASE_IS_POD(),
                aspTKNMinimalOracle(_originalOracle).BASE_IS_FRAX_PAIR(),
                aspTKNMinimalOracle(_originalOracle).spTkn(),
                aspTKNMinimalOracle(_originalOracle).UNDERLYING_TKN_CL_POOL()
            ),
            abi.encode(
                aspTKNMinimalOracle(_originalOracle).BASE_CONVERSION_CHAINLINK_FEED(),
                aspTKNMinimalOracle(_originalOracle).BASE_CONVERSION_CL_POOL(),
                aspTKNMinimalOracle(_originalOracle).BASE_CONVERSION_DIA_FEED(),
                aspTKNMinimalOracle(_originalOracle).CHAINLINK_BASE_PRICE_FEED(),
                aspTKNMinimalOracle(_originalOracle).CHAINLINK_QUOTE_PRICE_FEED(),
                _diaOracle,
                address(aspTKNMinimalOracle(_originalOracle).V2_RESERVES())
            ),
            uint96(uint160(_originalOracle) % 2 ** 96)
        );
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IDecentralizedIndex.sol";
import "../interfaces/IDexAdapter.sol";
import "../interfaces/IFraxlendPair.sol";
import "../interfaces/IIndexManager.sol";
import "../interfaces/IIndexUtils.sol";
import "../interfaces/ILeverageManager.sol";
import "../interfaces/ILeverageManagerAccessControl.sol";

interface IAspTknFactory {
    function minimumDepositAtCreation() external view returns (uint256);

    function create(
        string memory _name,
        string memory _symbol,
        bool _isSelfLendingPod,
        IDecentralizedIndex _pod,
        IDexAdapter _dexAdapter,
        IIndexUtils _indexUtils,
        uint96 _salt
    ) external returns (address _aspAddy);

    function getNewCaFromParams(
        string memory _name,
        string memory _symbol,
        bool _isSelfLendingPod,
        IDecentralizedIndex _pod,
        IDexAdapter _dexAdapter,
        IIndexUtils _indexUtils,
        uint96 _salt
    ) external view returns (address);
}

interface IAspTknOracleFactory {
    function create(address _aspTKN, bytes memory _requiredImmutables, bytes memory _optionalImmutables, uint96 _salt)
        external
        returns (address _oracleAddress);
}

interface IAspTkn {
    function setPod(IDecentralizedIndex _pod) external;
}

interface IAspTknOracle {
    function setSpTknAndDependencies(address _spTkn) external;
}

interface IFraxlendPairFactory {
    function defaultDepositAmt() external view returns (uint256);

    function deploy(bytes memory _configData) external returns (address _pairAddress);
}

contract LeverageFactory is Ownable {
    using SafeERC20 for IERC20;

    address public indexUtils;
    address public dexAdapter;
    address public indexManager;
    address public leverageManager;
    address public aspTknFactory;
    address public aspTknOracleFactory;
    address public fraxlendPairFactory;
    address public aspOwnershipTransfer;

    event AddLvfSupportForPod(address _pod, address _aspTkn, address _aspTknOracle, address _lendingPair);

    event CreateLvfPod(address _pod, address _aspTkn, address _aspTknOracle, address _lendingPair);

    event SetAspOwnershipTransfer(address _prevOwner, address _newOwner);

    event TransferContractOwnership(address _ownable, address _currentOwner, address _newOwner);

    constructor(
        address _indexUtils,
        address _dexAdapter,
        address _indexManager,
        address _leverageManager,
        address _aspTknFactory,
        address _aspTknOracleFactory,
        address _fraxlendPairFactory,
        address _aspOwnershipTransfer
    ) Ownable(_msgSender()) {
        _setLevMgrAndFactories(
            _indexUtils,
            _dexAdapter,
            _indexManager,
            _leverageManager,
            _aspTknFactory,
            _aspTknOracleFactory,
            _fraxlendPairFactory
        );
        aspOwnershipTransfer = _aspOwnershipTransfer;
    }

    function createPodAndAddLvfSupport(
        address _borrowTkn,
        bytes memory _podConstructorArgs,
        bytes memory _aspTknOracleRequiredImmutables,
        bytes memory _aspTknOracleOptionalImmutables,
        bytes memory _fraxlendPairConfigData,
        bool _isSelfLending
    ) external returns (address _newPod, address _aspTkn, address _aspTknOracle, address _fraxlendPair) {
        require(ILeverageManagerAccessControl(leverageManager).flashSource(_borrowTkn) != address(0), "FS1");

        address _aspTknAddy = _getOrCreateAspTkn(
            _podConstructorArgs, "", "", address(0), dexAdapter, indexUtils, _isSelfLending, _isSelfLending
        );
        _aspTknOracle = IAspTknOracleFactory(aspTknOracleFactory).create(
            _aspTknAddy, _aspTknOracleRequiredImmutables, _aspTknOracleOptionalImmutables, 0
        );
        _fraxlendPair = _createFraxlendPair(_borrowTkn, _aspTknAddy, _aspTknOracle, _fraxlendPairConfigData);
        _newPod = _createPodWithArgs(_podConstructorArgs, _isSelfLending ? _fraxlendPair : address(0));

        if (_isSelfLending) {
            _aspTkn = _getOrCreateAspTkn(
                _podConstructorArgs, "", "", address(0), dexAdapter, indexUtils, _isSelfLending, false
            );
            require(_aspTkn == _aspTknAddy, "ASP");
        } else {
            _aspTkn = _aspTknAddy;
        }
        IAspTkn(_aspTkn).setPod(IDecentralizedIndex(_newPod));
        Ownable(_aspTkn).transferOwnership(aspOwnershipTransfer);
        IAspTknOracle(_aspTknOracle).setSpTknAndDependencies(IDecentralizedIndex(_newPod).lpStakingPool());

        // for not self-lending, turn on LVF
        _setLendingPairInLevMgr(_newPod, _fraxlendPair);

        IFraxlendPair(_fraxlendPair).addInterest(false);
        // NOTE: don't update exchange rate yet because the uniswap V2 pair has no
        // supply yet, so there technically is no exchange rate to set yet
        // IFraxlendPair(_fraxlendPair).updateExchangeRate();

        emit CreateLvfPod(_newPod, _aspTkn, _aspTknOracle, _fraxlendPair);
    }

    function addLvfSupportForPod(
        address _pod,
        bytes memory _aspTknOracleRequiredImmutables,
        bytes memory _aspTknOracleOptionalImmutables,
        bytes memory _fraxlendPairConfigData
    ) external onlyOwner returns (address _aspTkn, address _aspTknOracle, address _fraxlendPair) {
        address _borrowTkn = IDecentralizedIndex(_pod).PAIRED_LP_TOKEN();
        require(ILeverageManagerAccessControl(leverageManager).flashSource(_borrowTkn) != address(0), "FS2");
        uint256 _aspMinDep = IAspTknFactory(aspTknFactory).minimumDepositAtCreation();
        if (_aspMinDep > 0) {
            address _spTkn = IDecentralizedIndex(_pod).lpStakingPool();
            IERC20(_spTkn).safeTransferFrom(_msgSender(), address(this), _aspMinDep);
            IERC20(_spTkn).safeIncreaseAllowance(aspTknFactory, _aspMinDep);
        }
        _aspTkn = _getOrCreateAspTkn(
            "", IERC20Metadata(_pod).name(), IERC20Metadata(_pod).symbol(), _pod, dexAdapter, indexUtils, false, false
        );
        _aspTknOracle = IAspTknOracleFactory(aspTknOracleFactory).create(
            _aspTkn, _aspTknOracleRequiredImmutables, _aspTknOracleOptionalImmutables, 0
        );
        _fraxlendPair = _createFraxlendPair(_borrowTkn, _aspTkn, _aspTknOracle, _fraxlendPairConfigData);

        // this effectively is what "turns on" LVF for the pair
        _setLendingPairInLevMgr(_pod, _fraxlendPair);

        emit AddLvfSupportForPod(_pod, _aspTkn, _aspTknOracle, _fraxlendPair);
    }

    function transferContractOwnership(address _ownable, address _newOwner) external onlyOwner {
        address _owner = Ownable(_ownable).owner();
        Ownable(_ownable).transferOwnership(_newOwner);
        emit TransferContractOwnership(_ownable, _owner, _newOwner);
    }

    function setLevMgrAndFactories(
        address _indexUtils,
        address _dexAdapter,
        address _indexManager,
        address _leverageManager,
        address _aspTknFactory,
        address _aspTknOracleFactory,
        address _fraxlendPairFactory
    ) external onlyOwner {
        _setLevMgrAndFactories(
            _indexUtils,
            _dexAdapter,
            _indexManager,
            _leverageManager,
            _aspTknFactory,
            _aspTknOracleFactory,
            _fraxlendPairFactory
        );
    }

    function setAspOwnershipTransfer(address _newOwner) external onlyOwner {
        address _current = aspOwnershipTransfer;
        aspOwnershipTransfer = _newOwner;
        emit SetAspOwnershipTransfer(_current, _newOwner);
    }

    function _setLendingPairInLevMgr(address _pod, address _fraxlendPair) internal {
        ILeverageManagerAccessControl(leverageManager).setLendingPair(_pod, _fraxlendPair);
    }

    function _buildFinalFraxlendConfigData(
        address _borrowTkn,
        address _aspTkn,
        address _aspTknOracle,
        bytes memory _providedData
    ) internal pure returns (bytes memory _finalConfigData) {
        (
            uint32 _maxOracleDeviation,
            address _rateContract,
            uint64 _fullUtilizationRate,
            uint256 _maxLTV,
            uint256 _liquidationFee,
            uint256 _protocolLiquidationFee
        ) = abi.decode(_providedData, (uint32, address, uint64, uint256, uint256, uint256));
        _finalConfigData = abi.encode(
            _borrowTkn,
            _aspTkn,
            _aspTknOracle,
            _maxOracleDeviation,
            _rateContract,
            _fullUtilizationRate,
            _maxLTV,
            _liquidationFee,
            _protocolLiquidationFee
        );
    }

    function _createFraxlendPair(
        address _borrowTkn,
        address _aspTkn,
        address _aspTknOracle,
        bytes memory _fraxlendPairConfigData
    ) internal returns (address _fraxlendPair) {
        bytes memory _finalFraxlendPairConfig =
            _buildFinalFraxlendConfigData(_borrowTkn, _aspTkn, _aspTknOracle, _fraxlendPairConfigData);
        uint256 _fraxMinDep = IFraxlendPairFactory(fraxlendPairFactory).defaultDepositAmt();
        if (_fraxMinDep > 0) {
            IERC20(_borrowTkn).safeTransferFrom(_msgSender(), address(this), _fraxMinDep);
            IERC20(_borrowTkn).safeIncreaseAllowance(fraxlendPairFactory, _fraxMinDep);
        }
        _fraxlendPair = IFraxlendPairFactory(fraxlendPairFactory).deploy(_finalFraxlendPairConfig);
    }

    function _getOrCreateAspTkn(
        bytes memory _podConstructorArgs,
        string memory _podName,
        string memory _podSymbol,
        address _pod,
        address _dexAdapter,
        address _indexUtils,
        bool _isSelfLending,
        bool _onlyComputeAddress
    ) internal returns (address _aspTkn) {
        if (_podConstructorArgs.length > 0) {
            (_podName, _podSymbol,,,) = abi.decode(_podConstructorArgs, (string, string, bytes, bytes, address));
        }
        string memory _aspName = string.concat("Auto Compounding LP for ", _podName);
        string memory _aspSymbol = string.concat("as", _podSymbol);
        if (_onlyComputeAddress) {
            _aspTkn = IAspTknFactory(aspTknFactory).getNewCaFromParams(
                _aspName,
                _aspSymbol,
                _isSelfLending,
                IDecentralizedIndex(_pod),
                IDexAdapter(_dexAdapter),
                IIndexUtils(_indexUtils),
                0
            );
        } else {
            _aspTkn = IAspTknFactory(aspTknFactory).create(
                _aspName,
                _aspSymbol,
                _isSelfLending,
                IDecentralizedIndex(_pod),
                IDexAdapter(_dexAdapter),
                IIndexUtils(_indexUtils),
                0
            );
        }
    }

    function _createPodWithArgs(bytes memory _podConstructorArgs, address _overridePairedLpTkn)
        internal
        returns (address _newPod)
    {
        (
            string memory indexName,
            string memory indexSymbol,
            bytes memory baseConfig,
            bytes memory immutables,
            address owner
        ) = abi.decode(_podConstructorArgs, (string, string, bytes, bytes, address));
        _newPod = IIndexManager(indexManager).deployNewIndex(
            indexName,
            indexSymbol,
            baseConfig,
            _overridePairedLpTkn == address(0)
                ? immutables
                : _getSelfLendingPodImmutables(_overridePairedLpTkn, immutables),
            owner
        );
    }

    function _getSelfLendingPodImmutables(address _fraxlendPair, bytes memory _immutables)
        internal
        pure
        returns (bytes memory)
    {
        (
            ,
            address _lpRewardsToken,
            address _dai,
            address _feeRouter,
            address _rewardsWhitelister,
            address _v3TwapUtils,
            address _dexAdapter
        ) = abi.decode(_immutables, (address, address, address, address, address, address, address));
        return
            abi.encode(_fraxlendPair, _lpRewardsToken, _dai, _feeRouter, _rewardsWhitelister, _v3TwapUtils, _dexAdapter);
    }

    function _setLevMgrAndFactories(
        address _indexUtils,
        address _dexAdapter,
        address _indexManager,
        address _leverageManager,
        address _aspTknFactory,
        address _aspTknOracleFactory,
        address _fraxlendPairFactory
    ) internal {
        indexUtils = _indexUtils == address(0) ? indexUtils : _indexUtils;
        dexAdapter = _dexAdapter == address(0) ? dexAdapter : _dexAdapter;
        indexManager = _indexManager == address(0) ? indexManager : _indexManager;
        leverageManager = _leverageManager == address(0) ? leverageManager : _leverageManager;
        aspTknFactory = _aspTknFactory == address(0) ? aspTknFactory : _aspTknFactory;
        aspTknOracleFactory = _aspTknOracleFactory == address(0) ? aspTknOracleFactory : _aspTknOracleFactory;
        fraxlendPairFactory = _fraxlendPairFactory == address(0) ? fraxlendPairFactory : _fraxlendPairFactory;
    }
}

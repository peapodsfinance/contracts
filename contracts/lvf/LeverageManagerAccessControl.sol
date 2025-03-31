// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/IFlashLoanSource.sol";
import "../interfaces/IFraxlendPair.sol";
import "../interfaces/ILeverageManagerAccessControl.sol";

contract LeverageManagerAccessControl is Initializable, OwnableUpgradeable, ILeverageManagerAccessControl {
    // pod => pair
    mapping(address => address) public override lendingPairs;
    // borrow asset (USDC, DAI, pOHM, etc.) => flash source
    mapping(address => address) public override flashSource;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(_msgSender());
    }

    function setLendingPair(address _pod, address _pair) external override onlyOwner {
        if (_pair != address(0)) {
            require(IFraxlendPair(_pair).collateralContract() != address(0), "LPS");
        }
        lendingPairs[_pod] = _pair;
        emit SetPodLendingPair(_pod, _pair);
    }

    function setFlashSource(address _borrowAsset, address _flashSource) external override onlyOwner {
        if (_flashSource != address(0)) {
            require(IFlashLoanSource(_flashSource).source() != address(0), "AFS");
        }
        flashSource[_borrowAsset] = _flashSource;
        emit SetBorrowAssetFlashSource(_borrowAsset, _flashSource);
    }
}

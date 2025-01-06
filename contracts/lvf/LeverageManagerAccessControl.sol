// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IFlashLoanSource.sol";
import "../interfaces/IFraxlendPair.sol";
import "../interfaces/ILeverageManagerAccessControl.sol";

contract LeverageManagerAccessControl is Ownable, ILeverageManagerAccessControl {
    // pod => pair
    mapping(address => address) public override lendingPairs;
    // borrow asset (USDC, DAI, pOHM, etc.) => flash source
    mapping(address => address) public override flashSource;

    constructor() Ownable(_msgSender()) {}

    function setLendingPair(address _pod, address _pair) external override onlyOwner {
        if (_pair != address(0)) {
            require(IFraxlendPair(_pair).collateralContract() != address(0), "LPS");
        }
        lendingPairs[_pod] = _pair;
    }

    function setFlashSource(address _borrowAsset, address _flashSource) external override onlyOwner {
        if (_flashSource != address(0)) {
            require(IFlashLoanSource(_flashSource).source() != address(0), "AFS");
        }
        flashSource[_borrowAsset] = _flashSource;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Context.sol";
import "../interfaces/IFlashLoanSource.sol";

abstract contract FlashSourceBase is IFlashLoanSource, Context {
    address public immutable LEVERAGE_MANAGER;
    bool _initialised;

    modifier workflow(bool _starting) {
        if (_starting) {
            require(!_initialised, "F0");
            _initialised = true;
        } else {
            require(_initialised, "F1");
            _initialised = false;
        }
        _;
    }

    modifier onlyLeverageManager() {
        require(_msgSender() == LEVERAGE_MANAGER, "AUTH");
        _;
    }

    constructor(address _lvfManager) {
        LEVERAGE_MANAGER = _lvfManager;
    }
}

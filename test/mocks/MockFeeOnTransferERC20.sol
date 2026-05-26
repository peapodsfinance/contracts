// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice ERC20 that takes a 5% fee on transferFrom, used to verify StakingVault's FoT guard.
contract MockFeeOnTransferERC20 is ERC20 {
    uint256 public feeNumerator = 5;
    uint256 public constant FEE_DENOMINATOR = 100;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 fee = (amount * feeNumerator) / FEE_DENOMINATOR;
        uint256 sendAmount = amount - fee;
        _spendAllowance(from, _msgSender(), amount);
        _transfer(from, to, sendAmount);
        if (fee > 0) {
            _transfer(from, address(this), fee);
        }
        return true;
    }
}

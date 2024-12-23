// https://peapods.finance

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IPEAS.sol";

contract PEAS is IPEAS, ERC20 {
    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
        _mint(_msgSender(), 10_000_000 * 10 ** 18);
    }

    function burn(uint256 _amount) external virtual override {
        _burn(_msgSender(), _amount);
        emit Burn(_msgSender(), _amount);
    }
}

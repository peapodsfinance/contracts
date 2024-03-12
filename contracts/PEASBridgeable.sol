// https://peapods.finance

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import './interfaces/IERC20Bridgeable.sol';
import './PEAS.sol';

contract PEASBridgeable is IERC20Bridgeable, PEAS, ERC20Permit, Ownable {
  uint256 constant MAX_SUPPLY = 10_000_000 * 10 ** 18;
  mapping(address => bool) public minter;

  event Mint(address indexed minter, address indexed wallet, uint256 amount);
  event SetMinter(address indexed wallet, bool isMinter);

  constructor() PEAS('Wrapped PEAS', 'wPEAS') ERC20Permit('Wrapped PEAS') {
    _burn(_msgSender(), balanceOf(_msgSender()));
  }

  function burn(uint256 _amount) external override(IERC20Bridgeable, PEAS) {
    _burn(_msgSender(), _amount);
    emit Burn(_msgSender(), _amount);
  }

  function mint(address _wallet, uint256 _amount) external override {
    require(minter[_msgSender()], 'MINTER');
    require(totalSupply() + _amount <= MAX_SUPPLY, 'MAXSUP');
    _mint(_wallet, _amount);
    emit Mint(_msgSender(), _wallet, _amount);
  }

  function setMinter(address _wallet, bool _isMinter) external onlyOwner {
    require(minter[_wallet] != _isMinter, 'SWITCH');
    minter[_wallet] = _isMinter;
    emit SetMinter(_wallet, _isMinter);
  }
}

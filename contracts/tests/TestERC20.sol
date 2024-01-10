// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract TestERC20 is ERC20 {
  constructor() ERC20('xTestToken', 'xTST') {
    _mint(_msgSender(), 10_000_000 * 10 ** 18);
  }

  function burn(uint256 _amount) external {
    _burn(_msgSender(), _amount);
  }
}

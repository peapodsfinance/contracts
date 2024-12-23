// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IERC20Bridgeable is IERC20 {
    function burn(uint256 amount) external;

    function burnFrom(address wallet, uint256 amount) external;

    function mint(address wallet, uint256 amount) external;
}

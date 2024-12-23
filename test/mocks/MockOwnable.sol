// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MockOwnable is Ownable {
    constructor(address _owner) Ownable(_owner) {}
}

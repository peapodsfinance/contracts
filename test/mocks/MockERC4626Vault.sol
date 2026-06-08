// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Minimal canonical OpenZeppelin ERC4626 vault used as StakingVault's nested `asset()`
///         in tests. Its own `asset()` is the constructor token (e.g. a USDC mock). Uses OZ's
///         default share math (no decimals offset), so the first deposit is 1:1 and the share
///         price rises when assets are transferred in directly (simulated yield).
contract MockERC4626Vault is ERC4626 {
    constructor(IERC20 _asset, string memory _name, string memory _symbol) ERC4626(_asset) ERC20(_name, _symbol) {}
}

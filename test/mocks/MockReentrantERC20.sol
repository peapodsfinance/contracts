// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IStakingVaultReentry {
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function mint(uint256 shares, address receiver) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
}

/// @notice ERC20 that reenters the target vault during `transfer` / `transferFrom`, used to verify
///         `nonReentrant` is present on every StakingVault entry point.
contract MockReentrantERC20 is ERC20 {
    enum Mode { None, ReenterDeposit, ReenterMint, ReenterRedeem, ReenterWithdraw }

    Mode public mode;
    IStakingVaultReentry public vault;
    uint256 public reentrantAmount;
    address public reentrantOwner;
    bool private _reentrancyArmed;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function arm(IStakingVaultReentry _vault, Mode _mode, uint256 _amount, address _owner) external {
        vault = _vault;
        mode = _mode;
        reentrantAmount = _amount;
        reentrantOwner = _owner;
        _reentrancyArmed = true;
    }

    function _maybeReenter() internal {
        if (!_reentrancyArmed) return;
        _reentrancyArmed = false; // single-shot
        if (mode == Mode.ReenterDeposit) {
            vault.deposit(reentrantAmount, reentrantOwner);
        } else if (mode == Mode.ReenterMint) {
            vault.mint(reentrantAmount, reentrantOwner);
        } else if (mode == Mode.ReenterRedeem) {
            vault.redeem(reentrantAmount, reentrantOwner, reentrantOwner);
        } else if (mode == Mode.ReenterWithdraw) {
            vault.withdraw(reentrantAmount, reentrantOwner, reentrantOwner);
        }
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        bool ok = super.transfer(to, amount);
        _maybeReenter();
        return ok;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool ok = super.transferFrom(from, to, amount);
        _maybeReenter();
        return ok;
    }
}

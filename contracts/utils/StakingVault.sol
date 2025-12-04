// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title StakingVault
 * @notice A basic ERC4626 vault with whitelist allowing only whitelisted depositors to enter the vault
 * @dev Extends OpenZeppelin's ERC4626 implementation with additional access control features
 */
contract StakingVault is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    /// @notice user => amount underlying asset they can deposit
    mapping(address => uint256) public depositWhitelist;

    /// @notice Emitted when a depositor is added to the whitelist
    event DepositorWhitelisted(address indexed depositor, uint256 amount);

    /**
     * @notice Initializes the StakingVault contract
     * @param _asset The underlying ERC20 asset for the vault
     * @param _name The name of the vault token
     * @param _symbol The symbol of the vault token
     */
    constructor(IERC20 _asset, string memory _name, string memory _symbol)
        ERC4626(_asset)
        ERC20(_name, _symbol)
        Ownable(msg.sender)
    {}

    /**
     * @notice Adds multiple addresses to the deposit whitelist with max yield limits
     * @param depositors Array of addresses to whitelist
     * @param depositAmounts Array of maximum deposit amounts for each depositor
     */
    function setDepositorsWhitelistDepositAmounts(address[] calldata depositors, uint256[] calldata depositAmounts)
        external
        onlyOwner
    {
        require(depositors.length == depositAmounts.length, "Array length mismatch");
        for (uint256 i = 0; i < depositors.length; i++) {
            depositWhitelist[depositors[i]] = depositAmounts[i];
            emit DepositorWhitelisted(depositors[i], depositAmounts[i]);
        }
    }

    /**
     * @notice Override deposit to enforce whitelist
     * @param assets The amount of assets to deposit
     * @param receiver The address to receive the shares
     */
    function deposit(uint256 assets, address receiver) public virtual override returns (uint256) {
        depositWhitelist[msg.sender] -= assets;
        return super.deposit(assets, receiver);
    }

    /**
     * @notice Override mint to enforce whitelist
     * @param shares The amount of shares to mint
     * @param receiver The address to receive the shares
     */
    function mint(uint256 shares, address receiver) public virtual override returns (uint256) {
        uint256 assets = previewMint(shares);
        depositWhitelist[msg.sender] -= assets;
        return super.mint(shares, receiver);
    }

    /**
     * @notice Override redeem to enforce yield limits
     * @param shares The amount of shares to redeem
     * @param receiver The address to receive the assets
     * @param owner The address that owns the shares
     */
    function redeem(uint256 shares, address receiver, address owner) public virtual override returns (uint256 assets) {
        assets = previewRedeem(shares);
        depositWhitelist[owner] += assets;

        // Call parent with potentially adjusted assets
        // We need to burn the shares and transfer the capped assets
        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @notice Override withdraw to enforce yield limits
     * @param assets The amount of assets to withdraw
     * @param receiver The address to receive the assets
     * @param owner The address that owns the shares
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        returns (uint256 shares)
    {
        shares = previewWithdraw(assets);
        redeem(shares, receiver, owner);
    }
}

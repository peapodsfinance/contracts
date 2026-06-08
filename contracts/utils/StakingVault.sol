// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title StakingVault
 * @notice Whitelisted ERC4626 reimbursement vault. Each whitelisted user has a per-address
 *         `depositCap` representing the maximum *principal* (raw asset units deposited)
 *         they may have in the vault at any time. Users may freely redeem and re-deposit
 *         provided their currently-deposited principal stays at or below their cap.
 *
 *         The protocol team reimburses users by directly transferring asset tokens to this
 *         vault (e.g., `IERC20(asset()).transfer(stakingVault, amount)`); this increases
 *         `totalAssets()` and therefore the per-share asset value without minting new shares,
 *         so existing depositors withdraw more assets than they originally deposited.
 *
 *         Shares are *soulbound* — `transfer` and `transferFrom` revert. Allowance is still
 *         usable via `redeem`/`withdraw` (OZ `_spendAllowance` runs before `_burn`, which is
 *         exempted from the transfer restriction because its `to` is the zero address).
 *
 *         Vault share decimals = `asset.decimals() + 6` (per `_decimalsOffset()`), as a
 *         defence against the first-depositor share-inflation attack. Operators integrating
 *         with wallets/explorers that assume 18 decimals must account for this.
 *
 *         When `asset()` is itself an ERC4626 whose own `asset()` is USDC, depositors can use the
 *         standard ERC4626 `deposit`/`mint` (supplying `asset()` shares directly) OR the convenience
 *         `depositFromUnderlyingAsset` (supplying USDC, which is wrapped into `asset()` shares and
 *         then deposited here in a single call). Both paths charge the same per-share `depositCap`.
 *
 * @dev Cap-restoration on redeem decouples from asset availability: an under-reimbursed
 *      vault will distribute available assets proportionally (ERC4626 default), but each
 *      user's cap-room is restored proportional to *shares burned*, not assets received.
 *      Rationale: a temporarily-underfunded vault must not permanently consume users'
 *      deposit allowance.
 */
contract StakingVault is ERC4626, Ownable2Step, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice user => maximum principal that may be deposited at any time
    mapping(address => uint256) public depositCap;

    /// @notice user => currently-deposited principal (raw asset units, excludes yield)
    mapping(address => uint256) public depositedPrincipal;

    /// @notice Emitted when an owner sets / updates a depositor's cap, or when principal changes
    ///         via deposit/mint/redeem/withdraw. Off-chain consumers can derive `maxDeposit`
    ///         from `(cap, currentPrincipal)` without replaying transfer logs.
    event DepositorWhitelisted(address indexed depositor, uint256 cap, uint256 currentPrincipal);

    error StakingVault__ReceiverMismatch(address expected, address actual);
    error StakingVault__NonTransferable();
    error StakingVault__ZeroAddress();
    error StakingVault__ZeroAsset();
    error StakingVault__ZeroAmount();
    error StakingVault__ZeroShares();
    error StakingVault__FeeOnTransferNotSupported();
    error StakingVault__ArrayLengthMismatch();
    error StakingVault__RenounceOwnershipDisabled();

    constructor(IERC20 _asset, string memory _name, string memory _symbol)
        ERC4626(_asset)
        ERC20(_name, _symbol)
        Ownable(msg.sender)
    {
        if (address(_asset) == address(0)) revert StakingVault__ZeroAsset();
    }

    /// @notice Sets the deposit cap (max principal in vault) for each address. Overwrites prior cap.
    /// @dev    Cap may be set below `depositedPrincipal[user]` — existing principal is grandfathered;
    ///         `maxDeposit` saturates to 0 until the user redeems below the new cap.
    ///         Duplicates in `depositors` last-write-wins; operator responsibility.
    function setDepositorsWhitelistDepositAmounts(address[] calldata depositors, uint256[] calldata depositAmounts)
        external
        onlyOwner
    {
        if (depositors.length != depositAmounts.length) revert StakingVault__ArrayLengthMismatch();
        for (uint256 i = 0; i < depositors.length; i++) {
            address depositor = depositors[i];
            if (depositor == address(0)) revert StakingVault__ZeroAddress();
            depositCap[depositor] = depositAmounts[i];
            emit DepositorWhitelisted(depositor, depositAmounts[i], depositedPrincipal[depositor]);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function renounceOwnership() public view override onlyOwner {
        revert StakingVault__RenounceOwnershipDisabled();
    }

    /// @notice Deposit assets, mint shares to caller. Cap-gating is enforced by super.deposit's
    ///         `maxDeposit(receiver)` check (our override returns remaining cap-room or 0 if paused).
    /// @dev    Principal mutation is DEFERRED until AFTER super.deposit succeeds. Mutating before
    ///         super would cause super's internal `maxDeposit(receiver)` check to see the
    ///         post-mutation state (P + assets), spuriously reverting any deposit > half remaining.
    ///         `nonReentrant` is the load-bearing protection against ERC777-style callback reentry;
    ///         the deferred-mutation order is defense-in-depth for the cross-direction reentrancy
    ///         class only — same-direction (deposit→deposit) requires `nonReentrant`.
    function deposit(uint256 assets, address receiver) public override nonReentrant whenNotPaused returns (uint256) {
        if (receiver != msg.sender) revert StakingVault__ReceiverMismatch(msg.sender, receiver);

        uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
        uint256 shares = super.deposit(assets, receiver);
        uint256 balanceAfter = IERC20(asset()).balanceOf(address(this));
        if (balanceAfter - balanceBefore != assets) revert StakingVault__FeeOnTransferNotSupported();

        uint256 newPrincipal = depositedPrincipal[msg.sender] + assets;
        depositedPrincipal[msg.sender] = newPrincipal;
        emit DepositorWhitelisted(msg.sender, depositCap[msg.sender], newPrincipal);
        return shares;
    }

    /// @notice Mint shares to caller. Cap-gating is enforced by super.mint's `maxMint(receiver)` check.
    /// @dev    Same ordering rationale as `deposit`. `super.mint` returns the asset amount it
    ///         charged (== previewMint(shares)); we debit principal by that exact amount.
    function mint(uint256 shares, address receiver) public override nonReentrant whenNotPaused returns (uint256) {
        if (receiver != msg.sender) revert StakingVault__ReceiverMismatch(msg.sender, receiver);

        uint256 balanceBefore = IERC20(asset()).balanceOf(address(this));
        uint256 assets = super.mint(shares, receiver);
        uint256 balanceAfter = IERC20(asset()).balanceOf(address(this));
        if (balanceAfter - balanceBefore != assets) revert StakingVault__FeeOnTransferNotSupported();

        uint256 newPrincipal = depositedPrincipal[msg.sender] + assets;
        depositedPrincipal[msg.sender] = newPrincipal;
        emit DepositorWhitelisted(msg.sender, depositCap[msg.sender], newPrincipal);
        return assets;
    }

    /// @notice One-step deposit denominated in the *underlying vault's* asset (e.g. USDC), for the
    ///         nested layout where `asset()` is itself an ERC4626 whose `asset()` is USDC. Performs:
    ///           1. Pull `underlyingAssetAmount` of `underlyingAsset()` (USDC) from the caller and
    ///              deposit it into `asset()` (the underlying ERC4626), minting that vault's shares
    ///              to THIS contract.
    ///           2. Deposit those freshly-minted vault shares into THIS vault, minting StakingVault
    ///              shares to `receiver`.
    ///         The caller must approve THIS contract to spend `underlyingAssetAmount` of
    ///         `underlyingAsset()` (USDC). It does NOT need to approve or hold any `asset()` shares.
    /// @dev    Cap-gating, principal tracking, soulbound, pause, and reentrancy semantics are
    ///         identical to `deposit`; the ONLY difference is the token the caller supplies.
    ///         Principal is charged in `asset()` units (underlying-vault shares ACTUALLY received),
    ///         not USDC units — so a user's `depositCap` means the same thing on either deposit path.
    ///
    ///         Share math must use the price BEFORE the underlying-vault shares enter our balance:
    ///         `asset()`-shares are minted to THIS contract in step 1, inflating `totalAssets()`
    ///         before we mint StakingVault shares. Using the post-deposit price would shortchange
    ///         the depositor (catastrophically for the first depositor, where `assetsBefore == 0`),
    ///         so we snapshot `(totalAssets, totalSupply)` first and reproduce OZ's
    ///         `_convertToShares(_, Floor)` against that snapshot — matching what a direct
    ///         `deposit(vaultShares, receiver)` would have minted.
    ///
    ///         `vaultShares` is measured as the actual `totalAssets()` delta (not the underlying
    ///         vault's return value or `previewDeposit`), so it is exact regardless of the
    ///         underlying vault's rounding and inherently fee-on-transfer-safe at the `asset()` layer.
    /// @param  underlyingAssetAmount amount of `underlyingAsset()` (USDC) to pull from the caller
    /// @param  receiver must equal `msg.sender` (soulbound / per-depositor principal accounting)
    /// @return shares StakingVault shares minted to `receiver`
    function depositFromUnderlyingAsset(uint256 underlyingAssetAmount, address receiver)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        if (receiver != msg.sender) revert StakingVault__ReceiverMismatch(msg.sender, receiver);
        if (underlyingAssetAmount == 0) revert StakingVault__ZeroAmount();

        IERC4626 underlyingVault = IERC4626(asset());
        IERC20 underlyingAssetToken = IERC20(underlyingVault.asset());

        // Pull USDC from caller; measure the actual amount received so a (hypothetical)
        // fee-on-transfer underlying asset cannot desync what we approve/deposit downstream.
        uint256 underlyingReceived = underlyingAssetToken.balanceOf(address(this));
        underlyingAssetToken.safeTransferFrom(msg.sender, address(this), underlyingAssetAmount);
        underlyingReceived = underlyingAssetToken.balanceOf(address(this)) - underlyingReceived;

        // Snapshot THIS vault's price state BEFORE the underlying-vault shares land in our balance.
        uint256 assetsBefore = totalAssets(); // asset()-shares held pre-deposit (OZ "A0")
        uint256 supplyBefore = totalSupply(); // unchanged until our _mint below (OZ "S0")

        // Step 1: USDC -> underlying-vault shares, credited to THIS contract.
        underlyingAssetToken.forceApprove(address(underlyingVault), underlyingReceived);
        underlyingVault.deposit(underlyingReceived, address(this));
        // Clear any residual approval (defense-in-depth; a compliant vault consumes it all).
        underlyingAssetToken.forceApprove(address(underlyingVault), 0);

        // Underlying-vault shares actually received == increase in our asset balance. This is the
        // "assets" deposited into THIS vault and the principal charged against the caller's cap.
        uint256 vaultShares = totalAssets() - assetsBefore;

        // Step 2: cap-gate exactly like `deposit` (super.deposit's maxDeposit check), same OZ error.
        uint256 maxAssets = maxDeposit(receiver);
        if (vaultShares > maxAssets) revert ERC4626ExceededMaxDeposit(receiver, vaultShares, maxAssets);

        // Mirror previewDeposit(vaultShares) at the PRE-deposit price (OZ _convertToShares, Floor).
        shares = Math.mulDiv(vaultShares, supplyBefore + 10 ** _decimalsOffset(), assetsBefore + 1, Math.Rounding.Floor);
        // Reverts (unwinding step 1 atomically) on dust that would mint nothing, protecting the
        // caller from depositing USDC for zero StakingVault shares.
        if (shares == 0) revert StakingVault__ZeroShares();

        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, vaultShares, shares);

        uint256 newPrincipal = depositedPrincipal[receiver] + vaultShares;
        depositedPrincipal[receiver] = newPrincipal;
        emit DepositorWhitelisted(receiver, depositCap[receiver], newPrincipal);
    }

    /// @notice Redeem shares for assets. NOT pause-gated — exits remain available at the vault layer.
    /// @dev    Snapshot `principalBefore` and `balanceBefore` BEFORE super.redeem, because super
    ///         burns shares (mutating `balanceOf(owner)`). Reading `balanceOf(owner)` after super
    ///         would yield post-burn balance, causing:
    ///         - full-redeem: balanceOf=0 → division by zero → DoS
    ///         - partial-redeem: divisor shrinks → over-credit (drains entire principal)
    ///         Cap restoration is proportional to shares burned, independent of assets received
    ///         (cap-room decouples from asset shortfall — see contract NatSpec).
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        uint256 principalBefore = depositedPrincipal[owner];
        uint256 balanceBefore = balanceOf(owner);

        assets = super.redeem(shares, receiver, owner);

        uint256 principalOut = balanceBefore == 0 ? 0 : Math.mulDiv(principalBefore, shares, balanceBefore);
        uint256 newPrincipal = principalBefore - principalOut;
        depositedPrincipal[owner] = newPrincipal;
        emit DepositorWhitelisted(owner, depositCap[owner], newPrincipal);
    }

    /// @notice Withdraw a specified asset amount, burning the necessary shares. NOT pause-gated.
    /// @dev    See `redeem` for snapshot rationale. Uses ceil-rounded share count (returned by
    ///         super.withdraw, matching what was burned); may credit principalOut up to 1 wei
    ///         more than strict proportional fairness — acceptable, in user's favor.
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        uint256 principalBefore = depositedPrincipal[owner];
        uint256 balanceBefore = balanceOf(owner);

        shares = super.withdraw(assets, receiver, owner);

        uint256 principalOut = balanceBefore == 0 ? 0 : Math.mulDiv(principalBefore, shares, balanceBefore);
        uint256 newPrincipal = principalBefore - principalOut;
        depositedPrincipal[owner] = newPrincipal;
        emit DepositorWhitelisted(owner, depositCap[owner], newPrincipal);
    }

    /// @notice Returns remaining deposit capacity for `receiver`. Reflects pause state.
    function maxDeposit(address receiver) public view override returns (uint256) {
        if (paused()) return 0;
        uint256 cap = depositCap[receiver];
        uint256 principal = depositedPrincipal[receiver];
        return cap > principal ? cap - principal : 0;
    }

    /// @notice Returns max shares mintable for `receiver`. Round-trip safe with `super.mint` cap check
    ///         (proof: `previewMint(previewDeposit(X)) ≤ X` for any X under floor/ceil rounding).
    function maxMint(address receiver) public view override returns (uint256) {
        if (paused()) return 0;
        return previewDeposit(maxDeposit(receiver));
    }

    /// @notice The asset of the underlying ERC4626 vault (i.e. `asset().asset()`, e.g. USDC) — the
    ///         token a caller supplies to `depositFromUnderlyingAsset`. Convenience for integrators
    ///         deciding which token to approve.
    function underlyingAsset() external view returns (address) {
        return IERC4626(asset()).asset();
    }

    /// @notice Returns 6. Adds 6 decimals of virtual-share offset to harden against
    ///         first-depositor inflation attacks (raises attacker cost by ~10^6×).
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    /// @notice Soulbound: reject all transfers between non-zero addresses. Mint (`from==0`)
    ///         and burn (`to==0`) are permitted so super's internal share movements work.
    /// @dev    `allowance` and `approve` remain functional because they don't call `_update`;
    ///         allowance is only spendable via `redeem`/`withdraw` (which burn via `to==0`).
    ///         Direct `transferFrom` reverts via this guard.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) revert StakingVault__NonTransferable();
        super._update(from, to, value);
    }
}

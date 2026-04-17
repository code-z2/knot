// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/// @title IGasTank
/// @notice Interface for the per-user Gas Tank escrow contract.
interface IGasTank {
    // ═══════════════════════════════════════════════════════════════════════════
    //                                 EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Emitted when USDC is deposited via the `deposit` function.
    event Deposited(address indexed from, uint256 amount);

    /// @notice Emitted when USDC is withdrawn instantly with cosigner approval.
    event Withdrawn(address indexed to, uint256 amount);

    /// @notice Emitted when USDC is withdrawn after the permissionless delay window.
    event PermissionlessWithdrawn(address indexed to, uint256 amount);

    /// @notice Emitted when the cosigner debits USDC for gas billing.
    event Debited(uint256 amount, address indexed to);

    /// @notice Emitted when non-USDC tokens are swept by the owner.
    event Swept(address indexed token, address indexed to, uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Caller is not the owner.
    error NotOwner();

    /// @dev Caller is not the cosigner.
    error NotCosigner();

    /// @dev The cosigner-gated path is disabled for this GasTank.
    error CosignerDisabled();

    /// @dev The cosigner signature deadline has expired.
    error DeadlineExpired();

    /// @dev The cosigner signature is invalid.
    error InvalidCosignerSignature();

    /// @dev Permissionless withdrawal is still within the active protocol collection window.
    error PermissionlessWithdrawalStillLocked(uint256 unlockTime);

    /// @dev Cannot sweep USDC — use withdraw or withdrawPermissionless instead.
    error CannotSweepUSDC();

    // ═══════════════════════════════════════════════════════════════════════════
    //                              FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Pull USDC from msg.sender. Emits Deposited for indexing.
    function deposit(uint256 amount) external;

    /// @notice Withdraw USDC instantly.
    /// @dev Managed mode requires a cosigner signature. Self-managed mode (`address(0)`) skips signature validation.
    function withdraw(uint256 amount, address to, uint256 deadline, bytes calldata cosignerSig) external;

    /// @notice Withdraw USDC without cosigner approval after the protocol collection window has elapsed.
    function withdrawPermissionless(uint256 amount, address to) external;

    /// @notice Cosigner debits USDC for gas billing.
    /// @dev Reverts with `CosignerDisabled` when deployed with `address(0)` as cosigner.
    function debit(uint256 amount, address to) external;

    /// @notice Owner recovers non-USDC tokens sent by mistake.
    function sweep(address token, address to) external;
}

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

    /// @notice Emitted when a forced withdrawal is initiated.
    event ForcedInitiated(uint256 amount, uint256 unlockTime);

    /// @notice Emitted when a forced withdrawal is claimed after the timelock.
    event ForcedClaimed(address indexed to, uint256 amount);

    /// @notice Emitted when a pending forced withdrawal is cancelled by the owner.
    event ForcedCancelled();

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

    /// @dev A forced withdrawal is already pending.
    error ForcedAlreadyPending();

    /// @dev No forced withdrawal is pending.
    error NoForcedPending();

    /// @dev The forced withdrawal timelock has not expired.
    error ForcedStillLocked();

    /// @dev Cannot sweep USDC — use withdraw or forced withdrawal instead.
    error CannotSweepUSDC();

    // ═══════════════════════════════════════════════════════════════════════════
    //                                STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Tracks a pending forced withdrawal.
    struct PendingWithdrawal {
        uint128 amount;
        uint64 unlockTime;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                              FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Pull USDC from msg.sender. Emits Deposited for indexing.
    function deposit(uint256 amount) external;

    /// @notice Withdraw USDC instantly.
    /// @dev Managed mode requires a cosigner signature. Self-managed mode (`address(0)`) skips signature validation.
    function withdraw(uint256 amount, address to, uint256 deadline, bytes calldata cosignerSig) external;

    /// @notice Initiate a forced withdrawal with a 4-hour timelock.
    function initiateForced(uint256 amount) external;

    /// @notice Claim a forced withdrawal after the timelock expires.
    function claimForced(address to) external;

    /// @notice Cancel a pending forced withdrawal.
    function cancelForced() external;

    /// @notice Cosigner debits USDC for gas billing.
    /// @dev Reverts with `CosignerDisabled` when deployed with `address(0)` as cosigner.
    function debit(uint256 amount, address to) external;

    /// @notice Owner recovers non-USDC tokens sent by mistake.
    function sweep(address token, address to) external;
}

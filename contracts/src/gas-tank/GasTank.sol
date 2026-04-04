// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin-contracts/utils/cryptography/EIP712.sol";

import {IGasTank} from "../interfaces/IGasTank.sol";

/// @title GasTank
/// @notice Per-user USDC escrow for gas sponsorship on Default chain.
///
/// @dev Architecture:
///      - One GasTank per user, deployed via CreateX (deterministic CREATE2 address).
///      - Owner = user's smart account.
///      - Cosigner = protocol operator for managed mode, or `address(0)` for self-managed mode.
///      - Balance is simply `USDC.balanceOf(address(this))` — no internal ledger.
///      - USDC can be sent to the CREATE2 address before deployment.
///
///      Deposit: User transfers USDC directly, or calls `deposit()` for event tracking.
///               Cross-chain deposits land via the user's existing order system —
///               the GasTank is just the `recipient` in ExecutionParams.
///
///      Withdrawal:
///        - Instant: Owner path. Managed mode requires cosigner co-sign (EIP-712).
///                   Self-managed mode (`COSIGNER == address(0)`) skips signature validation.
///        - Forced:  Owner alone, 4-hour timelock. Managed cosigner can debit outstanding fees during window.
///
///      Billing: Cosigner calls `debit()` to charge gas fees, directing USDC to the paymaster.
///               Disabled when `COSIGNER == address(0)`.
contract GasTank is IGasTank, EIP712 {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    //                               CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Timelock duration for forced withdrawals.
    uint256 public constant FORCED_DELAY = 4 hours;

    /// @dev EIP-712 typehash for the Withdraw struct.
    bytes32 private constant WITHDRAW_TYPEHASH =
        keccak256("Withdraw(uint256 amount,address to,uint256 nonce,uint256 deadline)");

    // ═══════════════════════════════════════════════════════════════════════════
    //                               IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The user's smart account that owns this GasTank.
    address public immutable OWNER;

    /// @notice The configured gas provider.
    /// @dev `address(0)` means self-managed mode and disables protocol debit while leaving owner withdrawal self-managed.
    address public immutable COSIGNER;

    /// @notice The USDC token contract.
    IERC20 public immutable USDC;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Monotonically increasing nonce for instant withdrawal replay protection.
    uint256 public withdrawNonce;

    /// @notice Pending forced withdrawal state.
    PendingWithdrawal public pendingWithdrawal;

    // ═══════════════════════════════════════════════════════════════════════════
    //                              CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /// @param _owner   The user's smart account address.
    /// @param _cosigner The protocol operator address, or `address(0)` for self-managed mode.
    /// @param _usdc    The USDC token address on Default chain.
    constructor(address _owner, address _cosigner, address _usdc) EIP712("KnotGasTank", "1") {
        OWNER = _owner;
        COSIGNER = _cosigner;
        USDC = IERC20(_usdc);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                               DEPOSIT
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IGasTank
    function deposit(uint256 amount) external {
        USDC.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         INSTANT WITHDRAWAL
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IGasTank
    function withdraw(uint256 amount, address to, uint256 deadline, bytes calldata cosignerSig) external {
        if (msg.sender != OWNER) {
            revert NotOwner();
        }
        if (block.timestamp > deadline) {
            revert DeadlineExpired();
        }

        uint256 nonce = withdrawNonce++;

        if (COSIGNER != address(0)) {
            bytes32 digest =
                _hashTypedDataV4(keccak256(abi.encode(WITHDRAW_TYPEHASH, amount, to, nonce, deadline)));

            if (ECDSA.recover(digest, cosignerSig) != COSIGNER) {
                revert InvalidCosignerSignature();
            }
        }

        USDC.safeTransfer(to, amount);
        emit Withdrawn(to, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         FORCED WITHDRAWAL
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IGasTank
    function initiateForced(uint256 amount) external {
        if (msg.sender != OWNER) {
            revert NotOwner();
        }
        if (pendingWithdrawal.amount != 0) {
            revert ForcedAlreadyPending();
        }

        uint64 unlockTime = SafeCast.toUint64(block.timestamp + FORCED_DELAY);
        pendingWithdrawal = PendingWithdrawal({amount: SafeCast.toUint128(amount), unlockTime: unlockTime});
        emit ForcedInitiated(amount, unlockTime);
    }

    /// @inheritdoc IGasTank
    function claimForced(address to) external {
        if (msg.sender != OWNER) {
            revert NotOwner();
        }

        PendingWithdrawal memory pw = pendingWithdrawal;
        if (pw.amount == 0) {
            revert NoForcedPending();
        }
        if (block.timestamp < pw.unlockTime) {
            revert ForcedStillLocked();
        }

        delete pendingWithdrawal;

        uint256 balance = USDC.balanceOf(address(this));
        uint256 claimable = pw.amount < balance ? pw.amount : balance;

        USDC.safeTransfer(to, claimable);
        emit ForcedClaimed(to, claimable);
    }

    /// @inheritdoc IGasTank
    function cancelForced() external {
        if (msg.sender != OWNER) {
            revert NotOwner();
        }
        delete pendingWithdrawal;
        emit ForcedCancelled();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                            COSIGNER BILLING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IGasTank
    function debit(uint256 amount, address to) external {
        if (COSIGNER == address(0)) {
            revert CosignerDisabled();
        }
        if (msg.sender != COSIGNER) {
            revert NotCosigner();
        }
        USDC.safeTransfer(to, amount);
        emit Debited(amount, to);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                           TOKEN RECOVERY
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IGasTank
    function sweep(address token, address to) external {
        if (msg.sender != OWNER) {
            revert NotOwner();
        }
        if (token == address(USDC)) {
            revert CannotSweepUSDC();
        }

        uint256 bal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(to, bal);
        emit Swept(token, to, bal);
    }
}

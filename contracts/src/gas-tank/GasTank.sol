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
///        - Permissionless: Owner alone after the rolling protocol collection window elapses.
///
///      Billing: Cosigner calls `debit()` to charge gas fees, directing USDC to the paymaster.
///               Each debit refreshes the rolling permissionless-withdrawal timer.
///               Disabled when `COSIGNER == address(0)`.
contract GasTank is IGasTank, EIP712 {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    //                               CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Delay after the last protocol collection before owner can withdraw without cosigner approval.
    uint256 public constant PERMISSIONLESS_WITHDRAW_DELAY = 30 days;

    /// @dev EIP-712 typehash for the Withdraw struct.
    bytes32 private constant WITHDRAW_TYPEHASH =
        keccak256("withdraw(uint256 amount,address to,uint256 nonce,uint256 deadline)");

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

    /// @notice Timestamp of the last protocol collection-window refresh.
    uint64 public lastProtocolCollectionAt;

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
        lastProtocolCollectionAt = SafeCast.toUint64(block.timestamp);
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
            bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(WITHDRAW_TYPEHASH, amount, to, nonce, deadline)));

            if (ECDSA.recover(digest, cosignerSig) != COSIGNER) {
                revert InvalidCosignerSignature();
            }
        }

        USDC.safeTransfer(to, amount);
        emit Withdrawn(to, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                    DELAYED PERMISSIONLESS WITHDRAWAL
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IGasTank
    function withdrawPermissionless(uint256 amount, address to) external {
        if (msg.sender != OWNER) {
            revert NotOwner();
        }

        if (COSIGNER != address(0)) {
            uint256 unlockTime = uint256(lastProtocolCollectionAt) + PERMISSIONLESS_WITHDRAW_DELAY;
            if (block.timestamp < unlockTime) {
                revert PermissionlessWithdrawalStillLocked(unlockTime);
            }
        }

        USDC.safeTransfer(to, amount);
        emit PermissionlessWithdrawn(to, amount);
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
        lastProtocolCollectionAt = SafeCast.toUint64(block.timestamp);
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

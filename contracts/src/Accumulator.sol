// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {Initializable} from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import {ERC1155Holder} from "openzeppelin-contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC721Holder} from "openzeppelin-contracts/token/ERC721/utils/ERC721Holder.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/utils/ReentrancyGuard.sol";

import {IAccumulator} from "./interfaces/IAccumulator.sol";
import {IMerkleVerifier} from "./interfaces/IMerkleVerifier.sol";
import {Call, ExecutionParams, FillState, FillStatus} from "./types/Structs.sol";

/// @title Accumulator
/// @notice Destination-chain receiver that gathers bridged tokens from one or more source chains
///         and executes the user's intent once explicitly triggered by an authorized caller.
///
/// @dev Two-step lifecycle:
///      1. ACCUMULATE — The SpokePool (or owner) delivers bridged tokens via `handleV3AcrossMessage`.
///         Tokens are tracked against a fillId derived from (salt, depositor, fillDeadline, sumOutput).
///         No execution occurs during accumulation.
///      2. EXECUTE — An authorized party calls `executeIntent` with ExecutionParams + Merkle proof.
///         The Accumulator hashes the params with plain keccak256 (stateless — not the verifying
///         contract), then calls back to the owner account's `verifyMerkleRoot` to check that the
///         hash belongs to a signed Merkle tree.
///
///      Three execution modes:
///        Mode 1 (Pure Transfer):        No destCalls; inputToken transferred directly to recipient.
///        Mode 2 (Transform + Transfer): DestCalls execute, then finalOutputToken sent to recipient.
///        Mode 3 (Execute Only):         DestCalls execute; no Accumulator-managed transfer.
///
///      Accumulation message format (encoded by Dispatcher._buildDestinationMessage):
///        abi.encode(salt, fromChainId, fillDeadline, depositor, sumOutput, outputToken)
contract Accumulator is Ownable, Initializable, IAccumulator, ERC1155Holder, ERC721Holder, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                  ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Caller is not the registered SpokePool or the owner.
    error UnrecognizedCaller(address caller);

    /// @dev The depositor in the message does not match the contract owner.
    error InvalidOriginator(address originator);

    /// @dev The token delivered by the SpokePool does not match the expected output token.
    error TokenMismatch(bytes32 fillId, address tokenSent, address expectedToken);

    /// @dev Reserved accounting invariant was broken.
    error ReservedAccountingInvariant(address token, uint256 reserved, uint256 releaseAmount);

    /// @dev No destination calls were provided, but final output token differs from input token.
    error InvalidFinalOutputTokenForDirectTransfer(address inputToken, address finalOutputToken);

    /// @dev Post-execution output balance is below the user's minimum.
    error InsufficientOutput(address token, uint256 available, uint256 required);

    /// @dev Fill has not reached the accumulation threshold yet.
    error ThresholdNotMet(bytes32 fillId, uint256 received, uint256 sumOutput);

    /// @dev Fill is not in the Accumulating state.
    error InvalidFillStatus(bytes32 fillId, FillStatus status);

    /// @dev Fill deadline has not expired yet (markStale called too early).
    error FillNotExpired(bytes32 fillId, uint32 fillDeadline);

    /// @dev The owner's Merkle signature verification failed.
    error InvalidMerkleSignature();

    /// @dev Caller is not the designated destination caller for this intent.
    error UnauthorizedDestinationCaller(address caller, address expected);

    /// @dev Mode 3 requires destination calls to be present.
    error DestCallsRequiredForExecuteOnly();

    /// @dev Mode 1 does not support destination calls.
    error DestCallsNotAllowedForDirectTransfer();

    // ═══════════════════════════════════════════════════════════════════════════
    //                                CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Sentinel address representing native ETH for `finalOutputToken`.
    ///      Used only for balance checks and transfer routing after destCalls produce native.
    address private constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev EIP-712 struct typehash for ExecutionParams.
    ///      The account wraps this struct hash with its domain separator to produce the chain-bound leaf.
    bytes32 private constant EXECUTION_PARAMS_TYPEHASH = keccak256(
        "ExecutionParams(bytes32 salt,uint32 fillDeadline,uint256 sumOutput,"
        "address outputToken,uint256 finalMinOutput,address finalOutputToken,"
        "address recipient,address destinationCaller,bytes32 destCallsHash)"
    );

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Across SpokePool authorized to deliver fills.
    address private spokePool;

    /// @notice Per-fill accumulation state, keyed by fill ID.
    mapping(bytes32 => FillState) public fills;

    /// @notice Reserved balances backing active fills, by token.
    mapping(address => uint256) public reservedByToken;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Emitted when tokens are accumulated for a fill.
    event FillAccumulated(
        bytes32 indexed fillId, address indexed inputToken, uint256 amount, uint256 totalReceived, uint256 sumOutput
    );

    /// @notice Emitted after executeIntent completes successfully.
    event FillExecuted(
        bytes32 indexed fillId,
        address indexed recipient,
        address finalOutputToken,
        uint256 requestedOutput,
        uint256 actualOutput,
        uint256[] sourceChainIds
    );

    /// @notice Emitted when accumulation expires and active reserved input is marked stale.
    event FillStale(bytes32 indexed fillId, uint32 fillDeadline, uint256 staleInput, uint256[] sourceChainIds);

    /// @notice Emitted when funds are returned to owner due to stale/late fill handling.
    event FillRefunded(bytes32 indexed fillId, uint256 refundedInput, uint256[] sourceChainIds);

    /// @notice Emitted when the accumulation threshold is met and the fill is ready for execution.
    event FillReady(bytes32 indexed fillId, uint256 totalReceived, uint256 sumOutput);

    // ═══════════════════════════════════════════════════════════════════════════
    //                            CONSTRUCTOR / INIT
    // ═══════════════════════════════════════════════════════════════════════════

    /// @param _userAccount Owner account (the UnifiedAccount on the destination chain).
    constructor(address _userAccount) Ownable(_userAccount) {}

    /// @notice One-time initialization of the SpokePool address (called by factory).
    function initialize(address _spokePool) external initializer {
        spokePool = _spokePool;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                            ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Update the authorized SpokePool address.
    function setSpokePool(address _spokePool) external onlyOwner {
        spokePool = _spokePool;
    }

    /// @notice Sweep currently unreserved token balance back to the owner (user account).
    /// @dev Reserved balances for active fills are never swept.
    function sweep(address token) external onlyOwner {
        uint256 available = _availableBalance(token);
        if (available > 0) _transferToken(token, owner(), available);
    }

    /// @notice Mark a fill as stale and refund reserved tokens to the owner.
    /// @dev V-002 fix: Allows the owner to recover partial fills that never reached sumOutput
    ///      and have no further fills arriving to trigger the stale branch in handleV3AcrossMessage.
    ///      Only callable after fillDeadline has passed.
    /// @param fillId The fill ID to mark as stale.
    function markStale(bytes32 fillId) external onlyOwner {
        FillState storage state = fills[fillId];

        if (state.status != FillStatus.Accumulating) {
            revert InvalidFillStatus(fillId, state.status);
        }
        if (block.timestamp <= state.fillDeadline) {
            revert FillNotExpired(fillId, state.fillDeadline);
        }

        uint256 staleInput = state.received;
        address token = state.inputToken;

        _releaseReserved(token, staleInput);
        state.received = 0;
        state.status = FillStatus.Stale;

        uint256 refund = staleInput;
        uint256 available = _availableBalance(token);
        if (refund > available) refund = available;
        if (refund > 0) _transferToken(token, owner(), refund);

        emit FillStale(fillId, state.fillDeadline, refund, state.sourceChainIds);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                    STEP 1: ACCUMULATE (SpokePool fills)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Across V3 callback. Called by the SpokePool after delivering bridged tokens,
    ///         or directly by the owner for same-chain participation.
    ///
    /// @dev Accumulation-only. No execution occurs here.
    ///      Message layout (encoded by Dispatcher._buildDestinationMessage):
    ///        (bytes32 salt, uint256 fromChainId, uint32 fillDeadline, address depositor, uint256 sumOutput, address outputToken)
    ///
    /// @param tokenSent The token address delivered by the SpokePool.
    /// @param amount    The amount of tokens delivered in this fill.
    /// @param message   Encoded payload from the Dispatcher.
    function handleV3AcrossMessage(
        address tokenSent,
        uint256 amount,
        address,
        /* relayer — unused */
        bytes memory message
    )
        external
        payable
        override
    {
        if (msg.sender != spokePool && msg.sender != owner()) {
            revert UnrecognizedCaller(msg.sender);
        }

        (
            bytes32 salt,
            uint256 fromChainId,
            uint32 fillDeadline,
            address depositor,
            uint256 sumOutput,
            address outputToken
        ) = abi.decode(message, (bytes32, uint256, uint32, address, uint256, address));

        // Only the account owner can originate intents targeting this accumulator.
        if (depositor != owner()) revert InvalidOriginator(depositor);

        // V-001 fix: Reject fills where the delivered token does not match the expected output token.
        // This prevents fill poisoning where an attacker front-runs with a different token.
        // fillId now includes outputToken so each token gets its own accumulation lane.
        bytes32 fillId = keccak256(abi.encode(salt, depositor, fillDeadline, sumOutput, outputToken));

        if (tokenSent != outputToken) {
            revert TokenMismatch(fillId, tokenSent, outputToken);
        }
        FillState storage state = fills[fillId];

        // Executed/refunded fills ignore duplicates.
        if (state.status == FillStatus.Executed || state.status == FillStatus.Refunded) {
            return;
        }

        // Once stale, any late arrival is immediately refunded.
        if (state.status == FillStatus.Stale) {
            _recordSourceChainId(state, fromChainId);
            uint256 refundAmount = amount;
            uint256 available = _availableBalance(tokenSent);
            if (refundAmount > available) {
                refundAmount = available;
            }
            if (refundAmount > 0) {
                _transferToken(tokenSent, owner(), refundAmount);
            }
            emit FillRefunded(fillId, refundAmount, state.sourceChainIds);
            return;
        }

        // Initialize state on first fill for this intent.
        if (state.received == 0 && state.inputToken == address(0)) {
            state.inputToken = tokenSent;
            state.sumOutput = sumOutput;
            state.fillDeadline = fillDeadline;
            state.status = FillStatus.Accumulating;
        }

        // Deadline expired: mark stale and auto-refund.
        if (block.timestamp > state.fillDeadline) {
            uint256 staleInput = state.received;
            address expectedToken = state.inputToken;

            _releaseReserved(expectedToken, staleInput);
            state.received = 0;
            _recordSourceChainId(state, fromChainId);
            state.status = FillStatus.Stale;

            uint256 staleRefund = staleInput;
            uint256 expectedAvailable = _availableBalance(expectedToken);
            if (staleRefund > expectedAvailable) {
                staleRefund = expectedAvailable;
            }
            if (staleRefund > 0) {
                _transferToken(expectedToken, owner(), staleRefund);
            }

            uint256 lateRefund = amount;
            uint256 lateAvailable = _availableBalance(tokenSent);
            if (lateRefund > lateAvailable) {
                lateRefund = lateAvailable;
            }
            if (lateRefund > 0) {
                _transferToken(tokenSent, owner(), lateRefund);
            }
            emit FillStale(fillId, state.fillDeadline, staleRefund, state.sourceChainIds);
            emit FillRefunded(fillId, lateRefund, state.sourceChainIds);
            return;
        }

        _recordSourceChainId(state, fromChainId);

        state.received += amount;
        reservedByToken[tokenSent] += amount;

        emit FillAccumulated(fillId, tokenSent, amount, state.received, sumOutput);

        // Signal readiness but do NOT execute.
        if (state.received >= sumOutput) {
            emit FillReady(fillId, state.received, sumOutput);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                    STEP 2: EXECUTE (Merkle-verified)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Execute an accumulated intent. Authorization is verified by hashing the
    ///         ExecutionParams with plain keccak256 and calling back to the owner account's
    ///         `verifyMerkleRoot` to check the leaf belongs to a signed Merkle tree.
    ///
    /// @dev Three execution modes based on `params.finalOutputToken` and destination calls:
    ///
    ///      Mode 1 — Pure Transfer (no destCalls, finalOutputToken != address(0)):
    ///        Transfers `min(finalMinOutput, available)` of inputToken to recipient.
    ///        Requires `finalOutputToken == inputToken` (what Across delivered).
    ///
    ///      Mode 2 — Transform + Transfer (destCalls present, finalOutputToken != address(0)):
    ///        Executes destCalls, then transfers `min(finalMinOutput, available)` of
    ///        finalOutputToken to recipient. Supports NATIVE sentinel for native output.
    ///        Reverts if post-execution balance < finalMinOutput.
    ///
    ///      Mode 3 — Execute Only (destCalls present, finalOutputToken == address(0)):
    ///        Executes destCalls. No Accumulator-managed transfer. DestCalls must handle
    ///        all fund movement (transfers, protocol deposits, etc).
    ///
    /// @param params      Execution parameters for the dest chain leg.
    /// @param merkleProof Sibling hashes proving the leaf belongs to the signed root.
    /// @param signature   Signature over `toEthSignedMessageHash(merkleRoot)`.
    function executeIntent(ExecutionParams calldata params, bytes32[] calldata merkleProof, bytes calldata signature)
        external
        nonReentrant
    {
        (bytes32 fillId, FillState storage state) = _validateAndTransition(params, merkleProof, signature);

        address finalOutputToken = params.finalOutputToken;
        bool hasDestCalls = params.destCalls.length > 0;

        uint256 actualOutput;

        if (!hasDestCalls && finalOutputToken != address(0)) {
            // ── Mode 1: Pure Transfer ──
            if (finalOutputToken != state.inputToken) {
                revert InvalidFinalOutputTokenForDirectTransfer(state.inputToken, finalOutputToken);
            }
            actualOutput = _transferOutput(state.inputToken, params.recipient, params.finalMinOutput);
            _sweepToken(state.inputToken);
        } else if (hasDestCalls && finalOutputToken != address(0)) {
            // ── Mode 2: Transform + Transfer ──
            _executeCalls(params.destCalls);
            actualOutput = _transferOutput(finalOutputToken, params.recipient, params.finalMinOutput);
            _sweepToken(finalOutputToken);
            if (finalOutputToken != state.inputToken) {
                _sweepToken(state.inputToken);
            }
        } else if (hasDestCalls && finalOutputToken == address(0)) {
            // ── Mode 3: Execute Only ──
            _executeCalls(params.destCalls);
            _sweepToken(state.inputToken);
        } else {
            revert DestCallsRequiredForExecuteOnly();
        }

        emit FillExecuted(
            fillId, params.recipient, finalOutputToken, params.finalMinOutput, actualOutput, state.sourceChainIds
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                       EXECUTE — INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Validates authorization via Merkle proof, checks fill status & threshold,
    ///      then marks the fill as Executed and releases reserved input tokens.
    function _validateAndTransition(
        ExecutionParams calldata params,
        bytes32[] calldata merkleProof,
        bytes calldata signature
    ) internal returns (bytes32 fillId, FillState storage state) {
        // Verify destination caller authorization.
        if (params.destinationCaller != address(0) && msg.sender != params.destinationCaller) {
            revert UnauthorizedDestinationCaller(msg.sender, params.destinationCaller);
        }

        // Compute the EIP-712 struct hash (pre-domain). The account wraps this with its
        // domain separator to produce the chain-bound leaf before walking the Merkle proof.
        bytes32 structHash = _hashExecutionParams(params);

        // Verify the owner signed a Merkle tree containing this leaf.
        if (
            IMerkleVerifier(owner()).verifyMerkleRoot(structHash, merkleProof, signature)
                != IMerkleVerifier.verifyMerkleRoot.selector
        ) {
            revert InvalidMerkleSignature();
        }

        // Derive the same fillId used during accumulation (includes outputToken per V-001 fix).
        fillId = keccak256(abi.encode(params.salt, owner(), params.fillDeadline, params.sumOutput, params.outputToken));
        state = fills[fillId];

        if (state.status != FillStatus.Accumulating) {
            revert InvalidFillStatus(fillId, state.status);
        }

        if (state.received < state.sumOutput) {
            revert ThresholdNotMet(fillId, state.received, state.sumOutput);
        }

        state.status = FillStatus.Executed;
        _releaseReserved(state.inputToken, state.received);
    }

    /// @dev Computes the EIP-712 struct hash for ExecutionParams.
    ///      This is the pre-domain struct hash — the owner account wraps it with
    ///      `_hashTypedDataV4(structHash)` to produce the chain-bound leaf.
    function _hashExecutionParams(ExecutionParams calldata params) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                EXECUTION_PARAMS_TYPEHASH,
                params.salt,
                params.fillDeadline,
                params.sumOutput,
                params.outputToken,
                params.finalMinOutput,
                params.finalOutputToken,
                params.recipient,
                params.destinationCaller,
                _hashCalls(params.destCalls)
            )
        );
    }

    /// @dev Hashes an array of Call structs for inclusion in the ExecutionParams leaf hash.
    function _hashCalls(Call[] calldata calls) internal pure returns (bytes32) {
        if (calls.length == 0) return bytes32(0);
        bytes32[] memory hashes = new bytes32[](calls.length);
        for (uint256 i; i < calls.length; i++) {
            hashes[i] = keccak256(abi.encode(calls[i].target, calls[i].value, keccak256(calls[i].data)));
        }
        return keccak256(abi.encodePacked(hashes));
    }

    /// @dev Enforces minimum output, transfers to recipient, and returns the amount sent.
    ///      Uses unreserved balance to prevent spending funds reserved for other active fills.
    function _transferOutput(address token, address recipient, uint256 minOutput) internal returns (uint256 sent) {
        uint256 available = _availableBalance(token);
        if (available < minOutput) {
            revert InsufficientOutput(token, available, minOutput);
        }

        sent = _min(minOutput, available);
        if (sent > 0) _transferToken(token, recipient, sent);
    }

    /// @dev Sweeps any remaining balance of `token` back to the owner.
    function _sweepToken(address token) internal {
        uint256 remainder = _availableBalance(token);
        if (remainder > 0) _transferToken(token, owner(), remainder);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          CALL EXECUTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Executes destination calls in-order and bubbles underlying reverts.
    function _executeCalls(Call[] calldata calls) internal {
        for (uint256 i; i < calls.length; i++) {
            Address.functionCallWithValue(calls[i].target, calls[i].data, calls[i].value);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          TOKEN HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Returns the balance of `token` held by this contract (ERC-20 or native ETH).
    function _balanceOf(address token) internal view returns (uint256) {
        return token == NATIVE ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

    /// @dev Returns the currently available (unreserved) balance for `token`.
    function _availableBalance(address token) internal view returns (uint256) {
        uint256 balance = _balanceOf(token);
        uint256 reserved = reservedByToken[token];
        if (balance < reserved) return 0;
        return balance - reserved;
    }

    /// @dev Transfers `amount` of `token` to `to` (ERC-20 or native ETH).
    function _transferToken(address token, address to, uint256 amount) internal {
        if (token == NATIVE) {
            Address.sendValue(payable(to), amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    /// @dev Releases `amount` from token-level reservation accounting.
    function _releaseReserved(address token, uint256 amount) internal {
        if (amount == 0) return;
        uint256 reserved = reservedByToken[token];
        if (amount > reserved) {
            revert ReservedAccountingInvariant(token, reserved, amount);
        }
        reservedByToken[token] -= amount;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @dev Appends source chain id once (deduplicated) for event/UI attribution.
    function _recordSourceChainId(FillState storage state, uint256 sourceChainId) internal {
        uint256 len = state.sourceChainIds.length;
        for (uint256 i; i < len; i++) {
            if (state.sourceChainIds[i] == sourceChainId) return;
        }
        state.sourceChainIds.push(sourceChainId);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                              RECEIVE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Accept native Token (needed for destCalls that unwrap wrapped token or produce native).
    receive() external payable {}
}

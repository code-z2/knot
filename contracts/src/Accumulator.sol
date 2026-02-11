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
import {Call, FillState, FillStatus} from "./types/Structs.sol";

/// @title Accumulator
/// @notice Destination-chain receiver that gathers bridged tokens from one or more source chains
///         and executes the user's intent once the accumulation threshold is met.
///
/// @dev Lifecycle:
///      1. Dispatcher(s) on source chain(s) call SpokePool.deposit, targeting this contract.
///      2. The SpokePool (or the owner directly for same-chain participation) delivers tokens
///         and calls `handleV3AcrossMessage` with the payload.
///      3. The Accumulator validates the caller (SpokePool or owner) and originator (owner).
///      4. Tokens accumulate per fill ID until `received >= sumOutput`.
///      5. On threshold: deduct fees → feeSponsor, execute destCalls, transfer finalOutputToken to recipient.
///
///      Message format (encoded by Dispatcher._buildDestinationMessage):
///        abi.encode(salt, fromChainId, fillDeadline, depositor, recipient, sumOutput, finalMinOutput,
///                   finalOutputToken, fees, feeSponsor, destCalls)
///
///      The Accumulator always transfers `finalOutputToken` to the recipient.
///      If destCalls is empty, the user must ensure `finalOutputToken == tokenSent`.
///      Any conversions (WETH→ETH, token swaps) are handled by the destCalls.
contract Accumulator is Ownable, Initializable, IAccumulator, ERC1155Holder, ERC721Holder, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                  ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Caller is not the registered SpokePool or the owner.
    error UnrecognizedCaller(address caller);

    /// @dev The depositor in the message does not match the contract owner.
    error InvalidOriginator(address originator);

    /// @dev Fee exceeds currently available locked input for this fill.
    error FeeExceedsInput(uint256 fee, uint256 input);

    /// @dev Reserved accounting invariant was broken.
    error ReservedAccountingInvariant(address token, uint256 reserved, uint256 releaseAmount);

    /// @dev No destination calls were provided, but final output token differs from input token.
    error InvalidFinalOutputTokenForDirectTransfer(address inputToken, address finalOutputToken);

    // ═══════════════════════════════════════════════════════════════════════════
    //                                CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Sentinel address representing native ETH.
    address private constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Across SpokePool authorized to deliver fills.
    address private SPOKE_POOL;

    /// @notice Per-fill accumulation state, keyed by fill ID (keccak256 of message).
    mapping(bytes32 => FillState) public fills;

    /// @notice Reserved balances backing active fills, by token.
    mapping(address => uint256) public reservedByToken;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Emitted after threshold is reached and execution path completes.
    /// @param requestedOutput User-requested minimum output (`finalMinOutput`).
    /// @param actualOutput Actual output sent to recipient during execution.
    event FillExecuted(
        bytes32 indexed fillId,
        address indexed recipient,
        address finalOutputToken,
        uint256 requestedOutput,
        uint256 actualOutput,
        uint256 feeDeducted,
        uint256[] sourceChainIds
    );

    /// @notice Emitted when accumulation expires and active reserved input is marked stale.
    event FillStale(bytes32 indexed fillId, uint32 fillDeadline, uint256 staleInput, uint256[] sourceChainIds);

    /// @notice Emitted when funds are returned to owner due to stale/late fill handling.
    event FillRefunded(bytes32 indexed fillId, uint256 refundedInput, uint256[] sourceChainIds);

    /// @notice Emitted when a non-matching token fill is ignored while still active.
    event FillTokenIgnored(bytes32 indexed fillId, address tokenSent, address expectedToken, uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════════
    //                            CONSTRUCTOR / INIT
    // ═══════════════════════════════════════════════════════════════════════════

    /// @param _userAccount Owner account (the UnifiedTokenAccount on the destination chain).
    constructor(address _userAccount) Ownable(_userAccount) {}

    /// @notice One-time initialization of the SpokePool address (called by factory).
    function initialize(address _spokePool) external initializer {
        SPOKE_POOL = _spokePool;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                            ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Update the authorized SpokePool address.
    function setSpokePool(address _spokePool) external onlyOwner {
        SPOKE_POOL = _spokePool;
    }

    /// @notice Sweep currently unreserved token balance back to the owner (user account).
    /// @dev Reserved balances for active fills are never swept.
    function sweep(address token) external onlyOwner {
        uint256 available = _availableBalance(token);
        if (available > 0) _transferToken(token, owner(), available);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                        ACROSS MESSAGE HANDLER
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Across V3 callback. Called by the SpokePool after delivering bridged tokens,
    ///         or directly by the owner for same-chain participation.
    ///
    /// @dev Message layout (encoded by Dispatcher._buildDestinationMessage):
    ///        (bytes32 salt, uint256 fromChainId, uint32 fillDeadline, address depositor, address recipient, uint256 sumOutput,
    ///         uint256 finalMinOutput, address finalOutputToken,
    ///         bytes32 fees, address feeSponsor, bytes destCalls)
    ///
    ///      `destCalls` is raw bytes — abi.encode(Call[]). Only decoded here on the destination chain.
    ///      Source chains pass it through without touching it.
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
        if (msg.sender != SPOKE_POOL && msg.sender != owner()) {
            revert UnrecognizedCaller(msg.sender);
        }

        // Decode the Dispatcher's message payload.
        (
            bytes32 salt,
            uint256 fromChainId,
            uint32 fillDeadline,
            address depositor,
            address recipient,
            uint256 sumOutput,
            uint256 finalMinOutput,
            address finalOutputToken,
            bytes32 fees,
            address feeSponsor,
            bytes memory destCallsEncoded
        ) = abi.decode(
            message, (bytes32, uint256, uint32, address, address, uint256, uint256, address, bytes32, address, bytes)
        );

        // Only the account owner can originate intents targeting this accumulator.
        if (depositor != owner()) revert InvalidOriginator(depositor);

        // fillId is derived from everything EXCEPT fromChainId, so fills from
        // different source chains accumulate into the same intent.
        bytes32 fillId = keccak256(
            abi.encode(
                salt,
                depositor,
                fillDeadline,
                recipient,
                sumOutput,
                finalMinOutput,
                finalOutputToken,
                fees,
                feeSponsor,
                destCallsEncoded
            )
        );
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
            state.recipient = recipient;
            state.sumOutput = sumOutput;
            state.fillDeadline = fillDeadline;
            state.finalMinOutput = finalMinOutput;
            state.finalOutputToken = finalOutputToken;
            state.fees = fees;
            state.feeSponsor = feeSponsor;
            state.status = FillStatus.Accumulating;
        }

        // Deadline is for accumulation as well. Expired fills become stale and auto-refund:
        // - previously accumulated expected input
        // - the current late arrival (even if token mismatches)
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

        // Active fill with mismatched token: accept transfer but do not account it into this fill.
        // Owner can recover unreserved tokens via `sweep`.
        if (state.inputToken != tokenSent) {
            if (amount > 0) {
                _transferToken(tokenSent, owner(), amount);
            }
            emit FillTokenIgnored(fillId, tokenSent, state.inputToken, amount);
            return;
        }

        // Track source chain ID for this fill.
        _recordSourceChainId(state, fromChainId);

        // Track the full delivered amount. `sumOutput` is only the minimum threshold
        // required to execute; arrivals can be higher and excess is handled on execute.
        state.received += amount;
        reservedByToken[tokenSent] += amount;

        // Execute once the accumulation threshold is reached.
        if (state.received >= sumOutput) {
            // Decode dest calls only here on the dest chain — source chains never touch this.
            Call[] memory destCalls;
            if (destCallsEncoded.length > 0) {
                destCalls = abi.decode(destCallsEncoded, (Call[]));
            }
            _executeIntent(fillId, state, destCalls);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          INTENT EXECUTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Main execution flow after accumulation threshold is reached.
    ///
    ///      1. Unpack fees: fees = (feeQuote << 128) | maxFee.
    ///         Actual fee = min(feeQuote, maxFee). Fee is paid to feeSponsor in the input token.
    ///
    ///      2. If destCalls present: execute swaps/conversions.
    ///         destCalls handle ALL token conversions (WETH→ETH, token swaps, etc.).
    ///         Reverts in destination calls bubble up.
    ///
    ///      3. Transfer finalOutputToken to recipient, capped at finalMinOutput when destCalls are present.
    ///      `state` is an in-memory snapshot from storage and used only for this execution pass.
    function _executeIntent(bytes32 fillId, FillState memory state, Call[] memory destCalls) internal nonReentrant {
        fills[fillId].status = FillStatus.Executed;

        uint256 lockedInput = state.received;
        _releaseReserved(state.inputToken, lockedInput);

        uint256 remainingInput = lockedInput;
        address inputToken = state.inputToken;

        // 1. Unpack fee: feeQuote (upper 128) and maxFee (lower 128).
        //    Actual fee = min(feeQuote, maxFee).
        uint128 maxFee = uint128(uint256(state.fees));
        uint128 feeQuote = uint128(uint256(state.fees) >> 128);
        uint256 actualFee = feeQuote < maxFee ? feeQuote : maxFee;

        // 2. Pay fee to the fee sponsor (in the received input token).
        if (actualFee > 0 && state.feeSponsor != address(0)) {
            if (actualFee > remainingInput) {
                revert FeeExceedsInput(actualFee, remainingInput);
            }
            _transferToken(inputToken, state.feeSponsor, actualFee);
            remainingInput -= actualFee;
        }

        // 3. Execute destination calls or direct transfer.
        uint256 actualOutput;
        if (destCalls.length > 0) {
            _executeCalls(destCalls);

            uint256 availableOutput = _availableBalance(state.finalOutputToken);
            uint256 toSend = _min(state.finalMinOutput, availableOutput);
            if (toSend > 0) {
                _transferToken(state.finalOutputToken, state.recipient, toSend);
            }
            actualOutput = toSend;

            // Return any unreserved remainder to owner.
            uint256 outputRemainder = _availableBalance(state.finalOutputToken);
            if (outputRemainder > 0) {
                _transferToken(state.finalOutputToken, owner(), outputRemainder);
            }
            if (state.finalOutputToken != inputToken) {
                uint256 inputRemainder = _availableBalance(inputToken);
                if (inputRemainder > 0) {
                    _transferToken(inputToken, owner(), inputRemainder);
                }
            }
        } else {
            // No destCalls: direct transfer path only supports the same token.
            if (state.finalOutputToken != inputToken) {
                revert InvalidFinalOutputTokenForDirectTransfer(inputToken, state.finalOutputToken);
            }
            uint256 availableInput = _availableBalance(inputToken);
            uint256 toSend = _min(state.finalMinOutput, availableInput);
            if (toSend > 0) {
                _transferToken(inputToken, state.recipient, toSend);
            }
            actualOutput = toSend;
            uint256 remainder = _availableBalance(inputToken);
            if (remainder > 0) {
                _transferToken(inputToken, owner(), remainder);
            }
        }

        emit FillExecuted(
            fillId,
            state.recipient,
            state.finalOutputToken,
            state.finalMinOutput,
            actualOutput,
            actualFee,
            state.sourceChainIds
        );
    }

    /// @dev Executes destination calls in-order and bubbles underlying reverts.
    function _executeCalls(Call[] memory calls) internal {
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
    ///      Reverts if release exceeds reserved amount to prevent silent underflow/clamp.
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

    /// @dev Accept native ETH (needed for WETH.withdraw() in destCalls and bridge fills).
    receive() external payable {}
}

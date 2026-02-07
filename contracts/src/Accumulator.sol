// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

import {Call, JobState, JobStatus} from "./types/Structs.sol";
import {Exec} from "./utils/Exec.sol";

/// @title Accumulator
/// @notice Destination-chain gatherer for a scatter-gather intent.
/// @dev
/// Flow (high level):
/// 1) The UnifiedTokenAccount batches source-chain actions (swap -> bridge) with a single signature.
/// 2) Across (or any messenger) delivers fills to this Accumulator on the destination chain.
/// 3) Each fill calls `handleMessage(...)` with the same payload, so the same intentHash is derived.
/// 4) The accumulator aggregates `amount` until `minInput` is reached.
/// 5) The account "approves" the job once it comes online on the destination chain (registerJob -> approve).
/// 6) If approved and accumulated: execute swaps, then pay recipient.
/// 7) If approval arrives after accumulation: refund to owner (late-approval policy) and mark refunded.
///
/// The accumulator is intentionally dumb: it does not verify signatures. Instead, it enforces:
/// - message caller is the trusted messenger
/// - job identity is derived from the payload + chainId + nonce
/// - only the account owner can approve a job
///
/// Edge cases handled:
/// - Duplicate fills: allowed; `received` is capped at `minInput`.
/// - Late approval: refunds and marks `Refunded`.
/// - No-swap flows: if swapCalls empty, `outputToken` must equal `inputToken` or refund.
/// - Swap failure: refund and mark `Refunded`.
contract Accumulator is Ownable {
    using SafeERC20 for IERC20;

    /// @dev Sentinel address representing native ETH in token fields.
    address private constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address private immutable TREASURY;
    address private immutable MESSENGER;

    mapping(bytes32 => JobState) public jobs;

    event JobApproved(bytes32 indexed intentId);
    event MultiChainIntentExecuted(
        bytes32 indexed intentId,
        address indexed user,
        address recipient,
        address inputToken,
        uint256 totalInput,
        uint256[] sourceChains
    );

    error AlreadyExecuted();
    error UnrecognizedCaller(address caller);

    /// @param _userAccount Owner account (UnifiedTokenAccount) that can approve/refund.
    /// @param _messenger Authorized caller for handleMessage (Across or equivalent).
    /// @param _treasury Treasury that can be swept manually.
    constructor(address _userAccount, address _messenger, address _treasury) Ownable(_userAccount) {
        TREASURY = _treasury;
        MESSENGER = _messenger;
    }

    /// @notice Called by the messenger when a fill arrives on this chain.
    /// @dev The messenger must be trusted because `amount` is trusted.
    /// Payload is opaque to the messenger; only this contract derives the intentHash.
    /// @param fromChain Source chain id of the fill (for UI aggregation).
    /// @param amount Amount delivered by the messenger for this fill.
    /// @param message Encoded job payload (input/output tokens, thresholds, swap calls, nonce).
    function handleMessage(uint256 fromChain, uint256 amount, bytes calldata message) external {
        _requiresMessenger();
        (
            address inputToken,
            address outputToken,
            address recipientOut,
            uint256 minInput,
            uint256 minOutput,
            Call[] memory swapCalls,
            uint256 nonce
        ) = _decodeMessage(message);

        bytes32 intentHash = _intentHash(inputToken, outputToken, recipientOut, minInput, minOutput, swapCalls, nonce);

        JobState storage job = jobs[intentHash];

        if (job.status == JobStatus.Executed || job.status == JobStatus.Refunded) return;

        if (!job.initialized) {
            job.inputToken = inputToken;
            job.initialized = true;
        } else if (job.inputToken != inputToken) {
            return;
        }

        job.received += amount;
        job.sourceChains.push(fromChain);

        if (job.received >= minInput) {
            job.received = minInput;
            job.status = JobStatus.Accumulated;
            if (job.approved) {
                _execute(intentHash, inputToken, outputToken, recipientOut, minInput, minOutput, swapCalls);
            }
        }
    }

    /// @notice Approves a job; if already accumulated, refunds immediately.
    /// @dev This is the "late approval" behavior requested to avoid silent auto-exec after the account
    /// becomes active. The UI can prompt the user to re-run if this happens.
    function approve(bytes32 intentHash) external onlyOwner {
        JobState storage job = jobs[intentHash];

        if (job.status == JobStatus.Executed || job.status == JobStatus.Refunded) revert AlreadyExecuted();

        if (job.approved) return;
        job.approved = true;

        if (job.status == JobStatus.Accumulated) {
            job.status = JobStatus.Refunded;
            _refundInput(job.received, job.inputToken);
            return;
        }

        emit JobApproved(intentHash);
    }

    /// @dev Executes swaps (if any), then pays recipient; otherwise refunds on failure.
    /// Important: approvals must be embedded inside swapCalls (first call), if needed.
    function _execute(
        bytes32 intentHash,
        address inputToken,
        address outputToken,
        address recipientOut,
        uint256 minInput,
        uint256 minOutput,
        Call[] memory swapCalls
    ) internal {
        JobState storage job = jobs[intentHash];
        job.status = JobStatus.Executed;

        bool ok = swapCalls.length == 0;
        if (swapCalls.length > 0) {
            ok = _trySwapCalls(swapCalls);
        }
        if (!ok || (outputToken != inputToken && swapCalls.length == 0)) {
            _refundInput(minInput, inputToken);
            job.status = JobStatus.Refunded;
            return;
        }

        uint256 amountOut = _balanceOf(outputToken);
        if (amountOut > minOutput) amountOut = minOutput;

        _transferToken(outputToken, recipientOut, amountOut);

        emit MultiChainIntentExecuted(intentHash, owner(), recipientOut, inputToken, minInput, job.sourceChains);
    }

    /// @dev Executes the swap call batch (approval must be included in swapCalls if needed).
    /// Returns false on the first failure; caller handles refund.
    function _trySwapCalls(Call[] memory swapCalls) internal returns (bool) {
        uint256 len = swapCalls.length;
        for (uint256 i = 0; i < len; i++) {
            Call memory call = swapCalls[i];
            bool ok = Exec.call(call.target, call.value, call.data, gasleft());
            if (!ok) return false;
        }
        return true;
    }

    /// @notice Manually sweep leftover balance of a token to treasury.
    /// @dev This is intentionally explicit so fees are collected only when desired.
    function sweep(address token) external onlyOwner {
        uint256 bal = _balanceOf(token);
        if (bal > 0) {
            _transferToken(token, TREASURY, bal);
        }
    }

    /// @dev Refund input token back to the account owner.
    /// Used when swap fails or when approval arrives after accumulation.
    function _refundInput(uint256 amount, address inputToken) internal {
        _transferToken(inputToken, owner(), amount);
    }

    /// @dev Returns true if the token address represents native ETH.
    function _isNative(address token) internal pure returns (bool) {
        return token == NATIVE;
    }

    /// @dev Returns the contract's balance of the given token (native or ERC20).
    function _balanceOf(address token) internal view returns (uint256) {
        return _isNative(token) ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

    /// @dev Transfers a token (native or ERC20) to a recipient.
    function _transferToken(address token, address to, uint256 amount) internal {
        if (_isNative(token)) {
            Address.sendValue(payable(to), amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    /// @dev Decodes the job payload encoded off-chain.
    /// Encoding must match: (inputToken, outputToken, recipient, minInput, minOutput, Call[] swapCalls, nonce).
    function _decodeMessage(bytes calldata message)
        internal
        pure
        returns (
            address inputToken,
            address outputToken,
            address recipientOut,
            uint256 minInput,
            uint256 minOutput,
            Call[] memory swapCalls,
            uint256 nonce
        )
    {
        return abi.decode(message, (address, address, address, uint256, uint256, Call[], uint256));
    }

    /// @dev Computes the job id (intent hash) from payload + chainId + nonce.
    /// The account uses the same derivation during registerJob (salt + jobId) to approve.
    function _intentHash(
        address inputToken,
        address outputToken,
        address recipientOut,
        uint256 minInput,
        uint256 minOutput,
        Call[] memory swapCalls,
        uint256 nonce
    ) internal view returns (bytes32) {
        bytes memory data = abi.encode(owner(), inputToken, outputToken, recipientOut, minInput, minOutput, swapCalls);
        bytes32 inner;
        assembly ("memory-safe") {
            inner := keccak256(add(data, 32), mload(data))
        }
        uint256 salt = (nonce << 60) | block.chainid;
        assembly ("memory-safe") {
            mstore(0x00, salt)
            mstore(0x20, inner)
            inner := keccak256(0x00, 0x40)
        }
        return inner;
    }

    /// @dev Restricts message handling to the messenger.
    /// This prevents arbitrary callers from faking `amount` or sourceChain.
    function _requiresMessenger() internal view {
        if (msg.sender != MESSENGER) revert UnrecognizedCaller(msg.sender);
    }

    receive() external payable {}
}

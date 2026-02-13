// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {Packing} from "openzeppelin-contracts/utils/Packing.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";

import {IDispatcher} from "../interfaces/IDispatcher.sol";
import {ISpokePool} from "../interfaces/ISpokePool.sol";
import {IWeth} from "../interfaces/IWeth.sol";

import {SuperIntentData, AcrossOrderData, Call, ChainCalls} from "../types/Structs.sol";

/// @title Dispatcher
/// @notice Abstract base for dispatching cross-chain orders through the Across spoke pool.
/// @dev Inheriting contracts must implement `_getAccumulator`.
///      Flow: executeCrossChainOrder → _resolveSuperIntentData → _callDeposit (SpokePool).
abstract contract Dispatcher is IDispatcher {
    using Packing for bytes32;
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                  ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Packed arrays have different lengths.
    error ArrayLengthMismatch();

    /// @dev Chain IDs embedded in packed arrays do not match at the same index.
    error IncorrectEncoding();

    /// @dev No entry in the packed arrays matches `block.chainid`.
    error NoInputForChain();

    /// @dev The order has already been dispatched (replay protection).
    error OrderAlreadyDispatched();

    /// @dev The number of configured source chains exceeds protocol bounds.
    error TooManySourceChains(uint256 provided, uint256 maxAllowed);

    /// @dev The number of chain call entries exceeds protocol bounds.
    error TooManyChainCalls(uint256 provided, uint256 maxAllowed);

    // ═══════════════════════════════════════════════════════════════════════════
    //                                CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Sentinel address representing native ETH.
    address private constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev EIP-712 typehash for the `ChainCalls` struct.
    ///      `calls` is typed as `bytes` — opaque from EIP-712's perspective, hashed as keccak256(calls).
    bytes32 private constant CHAIN_CALLS_TYPEHASH = keccak256("ChainCalls(uint256 chainId,bytes calls)");

    /// @dev EIP-712 typehash for the `SuperIntentData` struct.
    bytes32 internal constant SUPER_INTENT_TYPEHASH = keccak256(
        "SuperIntentData(uint256 destChainId,bytes32 salt,uint256 finalMinOutput,"
        "bytes32[] packedMinOutputs,bytes32[] packedInputAmounts,bytes32[] packedInputTokens,"
        "address outputToken,address finalOutputToken,address recipient,"
        "ChainCalls[] chainCalls)ChainCalls(uint256 chainId,bytes calls)"
    );
    /// @dev Maximum number of source-chain entries accepted in packed arrays.
    uint256 internal constant MAX_SOURCE_CHAINS = 10;
    /// @dev Maximum number of `chainCalls` entries (source chains + destination chain).
    uint256 internal constant MAX_CHAIN_CALLS = MAX_SOURCE_CHAINS + 1;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                CONFIG
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice WETH contract used to wrap native ETH before bridging (set at initialize).
    IWeth public WRAPPED_NATIVE_TOKEN;

    /// @notice Across SpokePool used for deposit calls (set at initialize).
    ISpokePool public SPOKE_POOL;

    // ═══════════════════════════════════════════════════════════════════════════
    //                                 STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Tracks dispatched job IDs to prevent replay.
    mapping(bytes32 jobId => bool dispatched) public jobIdToDispatched;

    // ═══════════════════════════════════════════════════════════════════════════
    //                           ABSTRACT HOOKS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Returns the accumulator address on the destination chain that receives bridged tokens.
    function _getAccumulator() internal view virtual returns (address);

    // ═══════════════════════════════════════════════════════════════════════════
    //                         SPOKE POOL INTERACTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Resolves and dispatches a cross-chain order through the SpokePool.
    ///      Replay protection is written before executing source calls/deposit.
    function _executeCrossChainOrder(SuperIntentData memory superIntentData, uint32 fillDeadline) internal virtual {
        (uint256 value, bytes32 jobId, bytes memory sourceCalls, AcrossOrderData memory acrossOrderData) =
            _resolveSuperIntentData(superIntentData, fillDeadline);

        if (jobIdToDispatched[jobId]) {
            revert OrderAlreadyDispatched();
        }
        jobIdToDispatched[jobId] = true;
        _executeCalls(sourceCalls);
        _callDeposit(fillDeadline, value, acrossOrderData);
        emit CrossChainOrderDispatched(jobId);
    }

    /// @dev Forwards the resolved order to `SPOKE_POOL.deposit`.
    ///      Uses `block.timestamp` as quote timestamp and caller-provided `fillDeadline`.
    function _callDeposit(uint32 fillDeadline, uint256 value, AcrossOrderData memory data) internal virtual {
        SPOKE_POOL.deposit{value: value}(
            data.depositor,
            data.recipient,
            data.inputToken,
            data.outputToken,
            data.inputAmount,
            data.outputAmount,
            data.destinationChainId,
            data.exclusiveRelayer,
            SafeCast.toUint32(block.timestamp),
            fillDeadline,
            data.exclusivityParameter,
            data.message
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          ORDER RESOLUTION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Resolves a `SuperIntentData` into the msg.value and `AcrossOrderData` needed for deposit.
    ///      - Unpacks and validates the per-chain packed arrays.
    ///      - Single pass over chainCalls to find source + dest entries, then early exit.
    ///      - Executes source-chain calls (preflight swaps/approvals) via Address.functionCallWithValue.
    ///      - Passes dest calls as raw bytes — no decode/re-encode. Accumulator decodes on dest chain.
    ///      - Wraps native ETH input to WETH address for the deposit.
    function _resolveSuperIntentData(SuperIntentData memory superIntentData, uint32 fillDeadline)
        internal
        returns (uint256 value, bytes32 jobId, bytes memory sourceCalls, AcrossOrderData memory acrossOrderData)
    {
        // Unpack per-chain data and accumulate the total output across all chains.
        (uint192 amount, address inputToken, uint192 minOutput, uint256 sumOutput) = _unpackVerifiedChainData(
            superIntentData.packedMinOutputs, superIntentData.packedInputAmounts, superIntentData.packedInputTokens
        );

        // Single pass: find source-chain calls and dest-chain calls.
        if (superIntentData.chainCalls.length > MAX_CHAIN_CALLS) {
            revert TooManyChainCalls(superIntentData.chainCalls.length, MAX_CHAIN_CALLS);
        }
        bytes memory destCalls;
        (sourceCalls, destCalls) =
            _findChainCalls(superIntentData.chainCalls, block.chainid, superIntentData.destChainId);

        // Build the destination message and derive the unique job ID from salt + message.
        // destCalls is passed as raw bytes — no decode on source chains.
        bytes memory message;
        (jobId, message) = _buildDestinationMessage(sumOutput, destCalls, superIntentData, fillDeadline);

        // Native ETH: swap sentinel → WETH address and forward value.
        if (inputToken == NATIVE) {
            inputToken = address(WRAPPED_NATIVE_TOKEN);
            value = amount;
        } else {
            IERC20(inputToken).forceApprove(address(SPOKE_POOL), amount);
        }

        return (
            value,
            jobId,
            sourceCalls,
            AcrossOrderData({
                depositor: _toBytes32(address(this)),
                recipient: _toBytes32(_getAccumulator()),
                inputToken: _toBytes32(inputToken),
                outputToken: _toBytes32(superIntentData.outputToken),
                inputAmount: amount,
                outputAmount: minOutput,
                destinationChainId: superIntentData.destChainId,
                exclusiveRelayer: bytes32(0),
                exclusivityParameter: uint32(0),
                message: message
            })
        );
    }

    /// @dev Encodes the cross-chain message consumed by the Accumulator and derives the job ID.
    ///      Job ID = keccak256(message), ensuring uniqueness per intent payload.
    ///
    ///      The message includes `salt` as a stable intent discriminator for the destination
    ///      accumulator fillId derivation, and `fillDeadline` as accumulation expiry.
    ///
    ///      The message does NOT include `outputToken` — the Accumulator works with whatever
    ///      token the bridge delivers (`tokenSent`). This avoids message divergence when the
    ///      same intent is dispatched from chains with different input tokens (e.g. native ETH
    ///      vs WETH), ensuring all fills accumulate into the same fill ID.
    ///
    ///      destCalls is raw bytes (abi.encode(Call[])) passed straight through.
    ///      Only the Accumulator on the destination chain decodes it.
    function _buildDestinationMessage(
        uint256 sumOutput,
        bytes memory destCalls,
        SuperIntentData memory data,
        uint32 fillDeadline
    ) internal view returns (bytes32 jobId, bytes memory message) {
        message = abi.encode(
            data.salt,
            block.chainid,
            fillDeadline,
            address(this),
            data.recipient,
            sumOutput,
            data.finalMinOutput,
            data.finalOutputToken,
            destCalls
        );

        jobId = keccak256(message);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                         CHAIN CALLS HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Single-pass lookup over `chainCalls` for two chain IDs (source + dest).
    ///      Returns the raw encoded calls for each, or empty bytes if not found.
    ///      Exits early once both are found.
    function _findChainCalls(ChainCalls[] memory chainCalls, uint256 sourceChainId, uint256 destChainId)
        internal
        pure
        returns (bytes memory sourceCalls, bytes memory destCalls)
    {
        bool foundSource;
        bool foundDest;
        for (uint256 i; i < chainCalls.length;) {
            uint256 id = chainCalls[i].chainId;
            if (!foundSource && id == sourceChainId && id != destChainId) {
                sourceCalls = chainCalls[i].calls;
                foundSource = true;
            } else if (!foundDest && id == destChainId) {
                destCalls = chainCalls[i].calls;
                foundDest = true;
            }
            if (foundSource && foundDest) break;
            unchecked {
                i++;
            }
        }
    }

    /// @dev Decodes and executes an array of `Call` from raw encoded bytes.
    ///      Uses OZ Address.functionCallWithValue — reverts on failure.
    ///      No-op if `encodedCalls` is empty.
    function _executeCalls(bytes memory encodedCalls) internal {
        if (encodedCalls.length == 0) return;
        Call[] memory calls = abi.decode(encodedCalls, (Call[]));
        for (uint256 i; i < calls.length;) {
            Address.functionCallWithValue(calls[i].target, calls[i].data, calls[i].value);
            unchecked {
                i++;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                        PACKED DATA UNPACKING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Unpacks and cross-validates the three packed arrays in a single pass.
    ///
    ///      Packing layouts (per entry):
    ///        packedMinOutputs  : [chainId uint64 | minOutput uint192]  (8 + 24 = 32 bytes)
    ///        packedInputAmounts: [chainId uint64 | amount    uint192]  (8 + 24 = 32 bytes)
    ///        packedInputTokens : [token address  | chainId   uint96 ]  (20 + 12 = 32 bytes)
    ///
    ///      Validates that the chain ID embedded in all three entries matches at each index.
    ///      Accumulates the sum of all minOutputs across chains.
    ///      Extracts this chain's amount, inputToken, and minOutput.
    function _unpackVerifiedChainData(
        bytes32[] memory packedMinOutputs,
        bytes32[] memory packedInputAmounts,
        bytes32[] memory packedInputTokens
    ) internal view returns (uint192 amount, address inputToken, uint192 minOutput, uint256 sum) {
        uint256 len = packedMinOutputs.length;
        if (len > MAX_SOURCE_CHAINS) {
            revert TooManySourceChains(len, MAX_SOURCE_CHAINS);
        }
        if (len != packedInputAmounts.length || len != packedInputTokens.length) {
            revert ArrayLengthMismatch();
        }

        bool found;
        uint64 targetChainId = uint64(block.chainid);

        for (uint256 i; i < len;) {
            // Extract the chain ID from each packed entry.
            uint64 minOutputChainId = uint64(packedMinOutputs[i].extract_32_8(0));
            uint64 amountChainId = uint64(packedInputAmounts[i].extract_32_8(0));
            uint64 tokenChainId = uint64(uint96(packedInputTokens[i].extract_32_12(20)));

            // All three arrays must agree on the chain ID at each index.
            if (minOutputChainId != amountChainId || minOutputChainId != tokenChainId) {
                revert IncorrectEncoding();
            }

            // Accumulate the total output across all chains.
            uint192 minOut = uint192(packedMinOutputs[i].extract_32_24(8));
            sum += minOut;

            // Extract this chain's specific values.
            if (minOutputChainId == targetChainId) {
                amount = uint192(packedInputAmounts[i].extract_32_24(8));
                inputToken = address(bytes20(packedInputTokens[i].extract_32_20(0)));
                minOutput = minOut;
                found = true;
            }

            unchecked {
                i++;
            }
        }

        if (!found) {
            revert NoInputForChain();
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                          EIP-712 HASHING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Computes the EIP-712 struct hash for `SuperIntentData`.
    ///      `packed*` arrays are hashed with `abi.encodePacked` as dynamic arrays of bytes32.
    function _hashSuperIntentData(SuperIntentData memory data) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                SUPER_INTENT_TYPEHASH,
                data.destChainId,
                data.salt,
                data.finalMinOutput,
                keccak256(abi.encodePacked(data.packedMinOutputs)),
                keccak256(abi.encodePacked(data.packedInputAmounts)),
                keccak256(abi.encodePacked(data.packedInputTokens)),
                data.outputToken,
                data.finalOutputToken,
                data.recipient,
                _hashChainCalls(data.chainCalls)
            )
        );
    }

    /// @dev Computes the EIP-712 array hash for an array of `ChainCalls` structs.
    ///      Each entry hashes as: keccak256(abi.encode(CHAIN_CALLS_TYPEHASH, chainId, keccak256(calls))).
    ///      `calls` is typed as `bytes` — opaque from EIP-712's perspective.
    function _hashChainCalls(ChainCalls[] memory chainCalls) internal pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](chainCalls.length);
        for (uint256 i; i < chainCalls.length;) {
            hashes[i] =
                keccak256(abi.encode(CHAIN_CALLS_TYPEHASH, chainCalls[i].chainId, keccak256(chainCalls[i].calls)));
            unchecked {
                i++;
            }
        }
        return keccak256(abi.encodePacked(hashes));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //                              UTILITIES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Left-pads an address into a bytes32 (Across V3 deposit format).
    function _toBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
}

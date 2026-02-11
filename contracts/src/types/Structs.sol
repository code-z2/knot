// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

struct Call {
    address target;
    uint256 value;
    bytes data;
}

/// @dev Per-chain calls. Each entry maps a chainId to its encoded Call[] payload.
///      Source chains execute their calls before bridging (preflight swaps/approvals).
///      The destination chain's calls are forwarded to the Accumulator for post-accumulation execution.
///      `calls` is abi.encode(Call[]) — decoded only by the chain that matches.
struct ChainCalls {
    uint256 chainId;
    bytes calls; // abi.encode(Call[])
}

/// @dev packedInputAmounts Packing: (chainId << 192) | amount. uint64 chainId + uint192 amount.
/// @dev packedInputTokens Packing: token 20 + chainId 12 = 32 bytes
/// @dev fees Packing: (feeQuote << 128) | maxFee. uint128 feeQuote + uint128 maxFee.
struct SuperIntentData {
    uint256 destChainId; // the chain id of the destination
    bytes32 salt; // used to prevent replay
    bytes32 fees; // expected fees the sponsor is willing to pay
    uint256 finalMinOutput; // min output token amount expected by the receipient if destCall is not empty. if it is empty, it means the user wants to receive the finalMinOutput == sum of packedMinOutputs
    bytes32[] packedMinOutputs; // min output token amount expected by the accumulator
    bytes32[] packedInputAmounts; // the amounts of input tokens sent to relayer per chain
    bytes32[] packedInputTokens; // the input tokens sent to relayer per chain
    address outputToken; // token requested from the Across relayer on the destination chain (not in Accumulator message)
    address finalOutputToken; // token expected by the receipient if destCall is not empty. if it is empty, it means the user wants to receive the outputToken == finalOutputToken
    address recipient; // final receipient
    address feeSponsor; // fee sponsor
    ChainCalls[] chainCalls; // per-chain calls (source preflight + destination post-accumulation)
}

struct OnchainCrossChainOrder {
    bytes32 orderDataType; // superintent typehash
    uint32 fillDeadline;
    bytes orderData; // superintent data
}

enum FillStatus {
    Accumulating,
    Executed,
    Stale,
    Refunded
}

/// @dev Used by the SpokePool.deposit call in Dispatcher (Across V3 bytes32 format).
struct AcrossOrderData {
    bytes32 depositor;
    bytes32 recipient;
    bytes32 inputToken;
    bytes32 outputToken;
    uint256 inputAmount;
    uint256 outputAmount;
    uint256 destinationChainId;
    bytes32 exclusiveRelayer;
    uint32 exclusivityParameter;
    bytes message;
}

/// @dev Tracks the state of a fill being accumulated on the destination chain.
///      Initialized on the first SpokePool delivery; executed once `received >= sumOutput`.
struct FillState {
    uint256 received; // tokens received so far from bridge fills
    address inputToken; // the token delivered by the SpokePool (set on first fill)
    address recipient; // final recipient of the output token
    uint256 sumOutput; // total output expected across all source chains (execution threshold)
    uint32 fillDeadline; // deadline after which accumulation is stale
    uint256 finalMinOutput; // min output of finalOutputToken expected by recipient
    address finalOutputToken; // the final token going to the recipient (may differ if destCalls convert)
    bytes32 fees; // packed fee data: (feeQuote << 128) | maxFee
    address feeSponsor; // address sponsoring the fees
    FillStatus status; // current fill lifecycle status
    uint256[] sourceChainIds; // chain IDs that contributed fills (for UI tracking)
}

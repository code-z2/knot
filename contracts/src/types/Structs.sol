// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

struct Call {
    address target;
    uint256 value;
    bytes data;
}

/// @dev Parameters for executing an accumulated intent on the destination chain.
///      Hashed with plain keccak256 (not EIP-712) by the Accumulator, then verified
///      via Merkle proof callback to the owner account.
///
///      Execution modes (determined by finalOutputToken + destCalls):
///        Mode 1 — Pure Transfer:        destCalls empty,   finalOutputToken != address(0).
///        Mode 2 — Transform + Transfer: destCalls present, finalOutputToken != address(0).
///        Mode 3 — Execute Only:         destCalls present, finalOutputToken == address(0).
struct ExecutionParams {
    bytes32 salt; // unique salt for fillId derivation + replay protection
    uint32 fillDeadline; // deadline after which accumulation is stale
    uint256 sumOutput; // total output expected across all source chains (execution threshold)
    address outputToken; // token Across delivers to accumulator (binds fillId to expected token)
    uint256 finalMinOutput; // min output of finalOutputToken enforced in Mode 1 & 2 (ignored in Mode 3)
    address finalOutputToken; // address(0) = Mode 3, NATIVE sentinel = native, else ERC-20
    address recipient; // final recipient (Mode 1 & 2 transfer target, ignored in Mode 3)
    address destinationCaller; // who can call executeIntent (address(0) = permissionless)
    Call[] destCalls; // post-accumulation calls executed on the owner account
}

/// @dev ERC-7683 OnchainCrossChainOrder — standard envelope for cross-chain intents.
///      `orderDataType` identifies the payload format (must match DISPATCH_ORDER_TYPEHASH).
///      `orderData` contains abi.encode(DispatchOrder).
struct OnchainCrossChainOrder {
    uint32 fillDeadline; // deadline for the fill on the destination chain
    bytes32 orderDataType; // EIP-712 typehash identifying the orderData format
    bytes orderData; // abi.encode(DispatchOrder)
}

/// @dev Order data for dispatching a single cross-chain leg via the SpokePool.
///      Encoded inside OnchainCrossChainOrder.orderData.
///      Each source chain gets its own dispatch call inside the executeX Call[] batch.
struct DispatchOrder {
    bytes32 salt; // shared salt across the intent (for fillId derivation)
    uint256 destChainId; // destination chain id
    address outputToken; // token requested from Across relayer on dest chain
    uint256 sumOutput; // total output expected across all source chains
    uint256 inputAmount; // amount of input token on this source chain
    address inputToken; // input token on this source chain
    uint256 minOutput; // min output for this source chain's fill
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
///      Initialized on the first SpokePool delivery. Execution is triggered
///      separately via `executeIntent` after `received >= sumOutput`.
struct FillState {
    uint256 received; // tokens received so far from bridge fills
    address inputToken; // the token delivered by the SpokePool (set on first fill)
    uint256 sumOutput; // total output expected across all source chains (execution threshold)
    uint32 fillDeadline; // deadline after which accumulation is stale
    FillStatus status; // current fill lifecycle status
    uint256[] sourceChainIds; // chain IDs that contributed fills (for UI tracking)
}

# AccumulatorModule — Module Type 2+3 (Executor + Fallback Handler)

## Purpose

Destination-chain fill tracking and intent execution. Replaces V1's `Accumulator` contract and `AccumulatorFactory`. Singleton module — one deployment serves all accounts. Per-account state via mappings.

## Dual Module Type

The AccumulatorModule is installed twice on each account:

1. **Type 3 (Fallback Handler):** Routes `handleV3AcrossMessage` and `executeIntent` selectors through the account's `fallback()` to this module.
2. **Type 2 (Executor):** Allows the module to call `executeFromExecutor` on the account to move tokens during intent execution.

```solidity
function isModuleType(uint256 typeID) external pure returns (bool) {
    return typeID == 2 || typeID == 3;
}
```

## State

```solidity
contract AccumulatorModule is IERC7579Module, ReentrancyGuard {
    // Per-account config
    mapping(address account => address spokePool) public spokePools;

    // Per-account fill tracking
    mapping(address account => mapping(bytes32 fillId => FillState)) public fills;

}
```

All state is in the module's own storage, keyed by account address. The account's fallback uses `call` (not `delegatecall`), so the module has its own storage context.

## Module Lifecycle

### onInstall (as Type 2 — Executor)

```solidity
function onInstall(bytes calldata data) external {
    address spokePool = abi.decode(data, (address));
    require(spokePool != address(0), "invalid spokePool");
    spokePools[msg.sender] = spokePool;
}
```

### onInstall (as Type 3 — Fallback Handler)

Selector registration is handled by the account's `installModule(3, ...)` call. The module receives the selector configuration via `data`.

### onUninstall

```solidity
function onUninstall(bytes calldata) external {
    delete spokePools[msg.sender];
    // Note: active fills remain in storage for potential recovery.
    // A migration function can be added for cleanup if needed.
}
```

## Accumulate: `handleV3AcrossMessage`

Called when the SpokePool fills an order. The SpokePool calls the account, which routes through `fallback()` → `call` to this module.

```solidity
function handleV3AcrossMessage(
    address tokenSent,
    uint256 amount,
    address,        // relayer — unused
    bytes memory message
) external payable {
    // msg.sender = account (forwarded by fallback via call)
    // _msgSender() = SpokePool (ERC-2771, original caller appended by fallback)
    address account = msg.sender;
    address caller = _msgSender();

    require(caller == spokePools[account], "not spokePool");

    (
        bytes32 salt,
        uint256 fromChainId,
        uint32 fillDeadline,
        address depositor,
        uint256 sumOutput,
        address outputToken
    ) = abi.decode(message, (bytes32, uint256, uint32, address, uint256, address));

    // Only the account owner can originate intents targeting this accumulator
    require(depositor == account, "not depositor");
    require(tokenSent == outputToken, "token mismatch");

    bytes32 fillId = keccak256(
        abi.encode(salt, depositor, fillDeadline, sumOutput, outputToken)
    );

    FillState storage state = fills[account][fillId];

    // Already executed — ignore duplicates
    if (state.status == FillStatus.Executed) return;

    // Stale — ignore (tokens remain in account, no refund needed)
    if (state.status == FillStatus.Stale) return;

    // Expired — mark stale (no token movement, just status update)
    if (block.timestamp > fillDeadline) {
        state.status = FillStatus.Stale;
        emit FillStale(fillId, fillDeadline);
        return;
    }

    // Initialize on first fill
    if (state.received == 0) {
        state.inputToken = tokenSent;
        state.sumOutput = sumOutput;
        state.fillDeadline = fillDeadline;
        state.status = FillStatus.Accumulating;
    }

    state.received += amount;
    _recordSourceChainId(state, fromChainId);

    emit FillAccumulated(fillId, tokenSent, amount, state.received, sumOutput);

    if (state.received >= sumOutput) {
        emit FillReady(fillId, state.received, sumOutput);
    }
}
```

### Tokens stay at the account

The SpokePool sends tokens to the account address (the Across deposit `recipient = account`). The module only tracks metadata — it never holds tokens. When a fill goes stale, no refund is needed because the tokens are already at the account.

## Execute: `executeIntent`

Called via UserOp → `account.execute([self.executeIntent(params)])` → fallback routes here.

```solidity
function executeIntent(ExecutionParams calldata params) external nonReentrant {
    address account = msg.sender;
    address caller = _msgSender(); // ERC-2771: who called the account
    require(caller == account, "not owner"); // must be self-call from execute

    bytes32 fillId = keccak256(
        abi.encode(params.salt, account, params.fillDeadline, params.sumOutput, params.outputToken)
    );

    FillState storage state = fills[account][fillId];

    require(state.status == FillStatus.Accumulating, "invalid status");
    require(state.received >= state.sumOutput, "threshold not met");

    state.status = FillStatus.Executed;

    // Execute based on mode
    bool hasDestCalls = params.destCalls.length > 0;
    address finalOut = params.finalOutputToken;

    if (!hasDestCalls && finalOut != address(0)) {
        // Mode 1: Pure Transfer
        _executeTransfer(account, finalOut, params.recipient, params.finalMinOutput);
    } else if (hasDestCalls && finalOut != address(0)) {
        // Mode 2: Transform + Transfer
        _executeCallsViaAccount(account, params.destCalls);
        _executeTransfer(account, finalOut, params.recipient, params.finalMinOutput);
    } else if (hasDestCalls && finalOut == address(0)) {
        // Mode 3: Execute Only
        _executeCallsViaAccount(account, params.destCalls);
    } else {
        revert("invalid mode");
    }

    emit FillExecuted(fillId, params.recipient, finalOut, params.finalMinOutput);
}
```

### Token Movement via `executeFromExecutor`

```solidity
function _executeTransfer(
    address account,
    address token,
    address recipient,
    uint256 amount
) internal {
    IERC7579Execution(account).executeFromExecutor(
        SINGLE_DEFAULT_MODE,
        _encodeSingle(
            token,
            0,
            abi.encodeCall(IERC20.transfer, (recipient, amount))
        )
    );
}

function _executeCallsViaAccount(
    address account,
    Call[] calldata calls
) internal {
    for (uint256 i; i < calls.length; i++) {
        IERC7579Execution(account).executeFromExecutor(
            SINGLE_DEFAULT_MODE,
            _encodeSingle(calls[i].target, calls[i].value, calls[i].data)
        );
    }
}
```

## Drop-On-Execution Semantics

The accumulator no longer maintains token reservations and no longer tries to invalidate fills on unrelated account executions.

Instead, the module owns a single bounded rule:

- fills accumulate directly against assets that already sit in the account
- the user can still repurpose those assets before deferred execution runs
- when `executeIntent` is finally attempted, the module checks whether the account still holds enough of the tracked input token to satisfy the accumulated fill
- if not, the module marks the fill `Dropped` and returns successfully

This gives the protocol the intended "fly or drop" behavior:

- if the funds are still there, the intent executes
- if the user already spent them, the later user action wins and the older fill is dropped

No hook-mediated generation tracking is required for this model.

## Call Flow: Accumulate

```
SpokePool → account.handleV3AcrossMessage(tokenSent, amount, relayer, message)
  → fallback() routes to AccumulatorModule via call
  → module: msg.sender = account, _msgSender() = SpokePool
  → verify SpokePool, decode message, track fill
  → tokens already at account — no movement
```

## Call Flow: Execute Intent

```
UserOp → EntryPoint → MerkleValidator ✓
  → account.execute(BATCH, [self.executeIntent(params)])
  → account calls self → fallback() routes to AccumulatorModule via call
  → module: msg.sender = account, _msgSender() = account (self-call)
  → verify self-call, validate fill state
  → if tracked input-token balance < accumulated fill amount: mark Dropped and return
  → otherwise executeFromExecutor → transfer tokens to recipient
```

## What V2 Eliminates from V1 Accumulator

| V1 | V2 |
|---|---|
| `Ownable(_userAccount)` | `msg.sender` is always the account |
| `IMerkleVerifier(owner()).verifyMerkleRoot(...)` | Not needed — UserOp already validated |
| `_hashExecutionParams()` / `EXECUTION_PARAMS_TYPEHASH` | Not needed — no struct hash verification |
| `merkleProof` + `signature` params on `executeIntent` | Removed |
| `destinationCaller` check | Removed — always owner-gated |
| `sweep()` | Not needed — tokens at account |
| Fill refund token transfers | Not needed — tokens at account |
| `Initializable` | `onInstall` handles config |
| Per-account contract deployment | Singleton with per-account mappings |
| `AccumulatorFactory` | Eliminated entirely |

## Stale Fill Handling

V1 required token transfers for stale fills (refunding from Accumulator to account). V2 reduces stale handling to a status update:

```
V1:  stale → transfer tokens from Accumulator → account   (gas + complexity)
V2:  stale → state.status = FillStatus.Stale              (just storage write)
```

Tokens are already at the account. Nothing to refund.

## Security Considerations

- **Owner-gated execution.** `executeIntent` checks `_msgSender() == account` (ERC-2771 self-call detection). Only the account can trigger execution, and only through a validated UserOp.
- **No signature handling.** The module never touches proofs or signatures. All cryptographic verification happens in MerkleValidator.
- **Fly or drop.** Pending fills are soft expectations. If the user later repurposes the tracked funds, `executeIntent` marks the fill `Dropped` instead of locking the account or trying to preserve pseudo-escrow.
- **Re-entrancy.** `executeIntent` is `nonReentrant`. The `executeFromExecutor` callbacks re-enter the account but not the module.

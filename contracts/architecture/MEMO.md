# Transaction Memo

A `bytes32` memo field attached to account executions. Emitted in an event, never stored. One memo per transaction/intent.

## Design

### Overloaded execute functions

```solidity
// Existing — no breaking change
function execute(Call[] calldata calls)
function execute(Call calldata call)

// With memo
function execute(Call[] calldata calls, bytes32 memo)
function execute(Call calldata call, bytes32 memo)
```

The memo variants emit `Memo(bytes32 indexed memo)` and delegate to the same internal execution logic. The `Call` struct is unchanged.

### Event

```solidity
event Memo(bytes32 indexed memo);
```

Emitted before execution when `memo != bytes32(0)`. Indexed for efficient log filtering — clients can query all transactions with a specific memo.

### No storage

The memo exists only in calldata and event logs. Zero SSTORE cost. The only additional gas is the `LOG2` opcode (~375 gas + 8 gas per topic byte).

## Encoding

The contract treats memo as opaque `bytes32`. Interpretation is client-side convention.

### Short text (up to 32 ASCII/UTF-8 chars)

```
"rent march" → 0x72656e74206d6172636800000000000000000000000000000000000000000000
```

Left-aligned, zero-padded. Client decodes by trimming trailing zeros and reading as UTF-8.

### Content digest (IPFS / off-chain pointer)

```
SHA-256 digest of CIDv1 content → bytes32
```

The 32-byte SHA-256 digest fits exactly. The client reconstructs the full CID by prepending the known codec/hash-function prefix (e.g. CIDv1 + dag-pb + sha256). This gives arbitrarily rich structured metadata off-chain while keeping on-chain cost fixed.

### Reference ID

```
keccak256(abi.encode("invoice", invoiceId)) → bytes32
```

Application-defined correlation key. Ties the on-chain tx to a backend record.

### Tagged format (future convention)

```
[4-byte type tag][28-byte payload]
```

First 4 bytes identify the memo type (text, CID digest, reference, etc). Remaining 28 bytes carry the payload. Extensible without contract changes.

## Scope

One memo per execution, not per `Call` in a batch. The memo describes the overall intent ("send rent to alice", "swap ETH for USDC"), not individual low-level calls (approve, transfer, etc).

## Integration with existing flows

### V1 (UnifiedAccount.executeX)

Add an overload that accepts `bytes32 memo`. The existing `executeX` signature remains unchanged.

### V2 (ERC-7579 execute)

The memo overload wraps the standard `execute(mode, executionCalldata)` with an additional `bytes32 memo` parameter. The memo is emitted before delegating to the standard execution path.

### Cross-chain intents

The memo is attached on the source chain execution. It does not propagate in the Across message — it's a source-chain annotation only. The destination-chain `executeIntent` can have its own memo if needed.

### UserOp integration

The memo is part of the `callData` field in the UserOp (encoded in the function selector + args). It is therefore bound by the UserOp signature — the user commits to the memo at signing time.

## Why not calldata encoding?

For EOA-to-EOA transfers, the standard pattern is putting UTF-8 bytes directly in the tx `data` field. This doesn't work for smart accounts because:

1. The `data` field is already the function calldata (selector + args)
2. Appending arbitrary bytes after ABI-encoded args is non-standard and fragile
3. The fallback handler in ERC-7579 would try to route unrecognized selectors

The function overload is the clean approach for smart accounts.

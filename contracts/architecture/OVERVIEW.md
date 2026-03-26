# V2 Architecture: ERC-7579 Modular Account

## Status

**Design phase.** The current V1 system (`UnifiedAccount`, `Dispatcher`, `Accumulator`, `AccumulatorFactory`) remains in production until V2 is fully implemented and tested.

## Summary

V2 migrates from a monolithic EIP-7702 smart account to a modular ERC-7579 architecture built on OpenZeppelin's `AccountERC7579`. The account becomes a thin shell with all domain logic moved into standard module types.

## Why

V1 packs everything into `UnifiedAccount`: Merkle verification, cross-chain dispatch, signature validation, replay protection, accumulator deployment, and execution. This makes the account difficult to audit, extend, and upgrade. Any change to dispatch logic requires redeploying the entire account implementation.

V2 separates concerns into independently deployable, auditable, and replaceable modules. The account itself is stock OpenZeppelin — no custom code beyond diamond override resolution.

## Architecture

```
                         EntryPoint (ERC-4337)
                              |
                        KnotAccount
                    (OZ AccountERC7579)
                    /    |      |
          MerkleValidator  CrossChainExecutor  AccumulatorModule
            (type 1)          (type 2)          (type 2+3)
```

### KnotAccount

Pure OZ shell. Inherits `AccountERC7579Hooked` + `SignerEIP7702` + `ERC7739`. No custom domain logic. The account stays hook-capable for future protocol policies, but the current bootstrap does not install an active hook module. The `fallback()` stays as OZ's default (`call`, not `delegatecall`). Module install/uninstall gated by `onlyEntryPointOrSelf`.

### MerkleValidator (Type 1 — Validator)

Validates all UserOperations via Merkle proof + P-256 signature. Each leaf in the Merkle tree is a `userOpHash` — the EIP-712 hash computed by the EntryPoint that binds every UserOp field + chainId + entryPoint address.

- Single-chain: 1 leaf, empty proof, signature directly over userOpHash.
- Cross-chain: N leaves (one per chain), Merkle proof per chain, one signature over root.
- Stores P-256 public key per account (set during `onInstall`).
- Provides `isValidSignature` (ERC-1271) for off-chain signature verification use cases.

### CrossChainExecutor (Type 2 — Executor)

Source-chain dispatch orchestrator. Handles Across SpokePool interaction.

- Salt replay tracking per account (`mapping(address => mapping(bytes32 => bool))`).
- Calls `executeFromExecutor` on the account to approve input tokens and call `SpokePool.depositV3`.
- Stores spokePool address and accumulator recipient per account (set during `onInstall`).

### AccumulatorModule (Type 2+3 — Executor + Fallback Handler)

Destination-chain fill tracking and intent execution. Singleton module with per-account state.

- **Fallback handler (type 3):** Routes `handleV3AcrossMessage` from the SpokePool through the account's fallback. Tracks fills per account in the module's own storage. Tokens stay at the account address (SpokePool sends to account as recipient).
- **Executor (type 2):** `executeIntent` moves tokens from the account via `executeFromExecutor`. Owner-gated — no signature verification in the module (the UserOp was already validated by MerkleValidator upstream). If the fill is ready but the account no longer holds enough of the required token, the module marks the fill `Dropped` and returns successfully instead of bricking the account.
- Stale fills are just a status update — no token refunds needed since tokens are already at the account.

### KnotConsumerHub + Goldsky (Global Orchestration)

Planned protocol-level coordination layer for cross-chain intents.

- `KnotConsumerHub` is the canonical global event surface for all `KnotAccount`s.
- The canonical `CrossChainExecutor` and `AccumulatorModule` singletons notify the hub directly, and the hub authenticates those module addresses.
- Goldsky watches the hub and orchestrates deferred destination execution.
- Durable deferred `UserOperation` storage remains outside Goldsky.

See [GOLDSKY_ORCHESTRATION.md](./GOLDSKY_ORCHESTRATION.md).

## Key Design Decisions

### All validation through EntryPoint

Every operation is a UserOperation. No custom `executeX`. The EntryPoint handles nonce management, gas accounting, and validation routing. The relayer becomes a bundler, using ERC-4337 paymasters for gasless UX.

### Homogeneous Merkle leaves

Every leaf is a `userOpHash`. No custom leaf types, no EIP-712 struct hashes in the tree. The EntryPoint computes the hash, binding every UserOp field. Single-chain and cross-chain use the same format — single-chain is just a 1-leaf tree with empty proof.

### Tokens at the account

The Across deposit `recipient` is the account address itself (not a separate accumulator contract). The SpokePool sends tokens to the account and calls `handleV3AcrossMessage` on the account. The fallback routes to AccumulatorModule, which tracks fills in its own storage. No token escrow, no factory, no per-account accumulator deployment.

### Direct-to-account fills with module-owned drop semantics

V2 no longer simulates escrow with account-level reservations.

- fills accumulate directly against assets that already sit in the account
- users retain control of those assets while the fill is pending
- `executeIntent` performs the final solvency check at execution time
- if the user has already repurposed the required funds, the module marks the fill `Dropped` and the later user action wins

This removes the two high-severity liveness hazards from the earlier hook-reservation design:

- over-reservation against actual balance cannot brick the account
- attacker-driven reserved-token pollution cannot turn execution into an unbounded gas loop

Global deferred-intent orchestration is handled separately by `KnotConsumerHub` + Goldsky. See [GOLDSKY_ORCHESTRATION.md](./GOLDSKY_ORCHESTRATION.md).

### Nonce channels for cross-chain

Pre-signed destination UserOps use a separate nonce key (channel) so they don't conflict with regular transactions the user makes while waiting for fills.

```
Regular:     | validatorAddr | 0x0000 | sequence |
Cross-chain: | validatorAddr | 0x0001 | sequence |
```

### Bootstrap via ECDSA fallback

First UserOp (before any validator is installed) uses `SignerEIP7702._rawSignatureValidation` — the EOA's ECDSA key. This UserOp installs all modules in a single batch.

## What V2 Eliminates from V1

| V1 Component | V2 Replacement |
|---|---|
| `UnifiedAccount.executeX` | EntryPoint + MerkleValidator |
| `UnifiedAccount.verifyMerkleRoot` | MerkleValidator.isValidSignature (ERC-1271) |
| `UnifiedAccount.dispatch` | CrossChainExecutor module |
| `UnifiedAccount.usedSalts` | CrossChainExecutor per-account tracking |
| `Dispatcher` abstract | CrossChainExecutor module |
| `Accumulator` contract (per-account) | AccumulatorModule singleton |
| `AccumulatorFactory` | Eliminated — no per-account deployment |
| `IMerkleVerifier` interface | Eliminated — not needed |
| `Accumulator._hashExecutionParams` | Eliminated — no struct hash verification |
| `Accumulator.reservedByToken` enforcement | Eliminated — no reservation hook |
| Fill refund token transfers | Eliminated — tokens already at account |
| `Accumulator.sweep` | Eliminated — tokens already at account |
| Custom `execute`/`executeBatch` | OZ `AccountERC7579.execute` (ERC-7579 modes) |

## Module Install (Init UserOp)

```solidity
execute(BATCH_MODE, [
    self.installModule(1, merkleValidator, abi.encode(p256PubKeyX, p256PubKeyY)),
    self.installModule(2, crossChainExecutor, abi.encode(spokePool)),
    self.installModule(2, accumulatorModule, abi.encode(spokePool)),
    self.installModule(3, accumulatorModule, abi.encodePacked(handleV3AcrossMessageSelector)),
    self.installModule(3, accumulatorModule, abi.encodePacked(executeIntentSelector)),
    self.installModule(3, accumulatorModule, abi.encodePacked(markStaleSelector))
])
```

## Documents

- [OVERVIEW.md](./OVERVIEW.md) — This document.
- [MERKLE_VALIDATOR.md](./MERKLE_VALIDATOR.md) — MerkleValidator module design.
- [CROSS_CHAIN_EXECUTOR.md](./CROSS_CHAIN_EXECUTOR.md) — CrossChainExecutor module design.
- [ACCUMULATOR_MODULE.md](./ACCUMULATOR_MODULE.md) — AccumulatorModule design.
- [GOLDSKY_ORCHESTRATION.md](./GOLDSKY_ORCHESTRATION.md) — Hub + Goldsky orchestration plan and rationale.
- [MIGRATION.md](./MIGRATION.md) — V1 to V2 migration plan.

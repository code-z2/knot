# V1 → V2 Migration Plan

## Status

**Not started.** V1 remains in production. V2 is in design phase. Migration begins when V2 contracts are implemented, tested, and audited.

## Prerequisites

Before migration:

1. V2 contracts implemented and unit tested (Foundry)
2. V2 contracts pass integration tests against forked mainnet
3. Bundler/paymaster infrastructure operational
4. SwiftUI UserOp lifecycle implemented (build, sign, submit, track)
5. Client-side Merkle tree construction working
6. Relayer adapted to bundler role (submits UserOps instead of direct calls)

## What Changes

### Contract Layer

| V1 | V2 | Action |
|---|---|---|
| `UnifiedAccount.sol` (358 lines) | `KnotAccount.sol` (~50 lines) | Replace — new implementation |
| `Dispatcher.sol` (154 lines) | `CrossChainExecutor.sol` | Replace — logic moves to module |
| `Accumulator.sol` (542 lines) | `AccumulatorModule.sol` | Replace — singleton module |
| `AccumulatorFactory.sol` (49 lines) | *(eliminated)* | Remove |
| `IMerkleVerifier.sol` | *(eliminated)* | Remove |
| `IDispatcher.sol` | *(eliminated)* | Remove |
| `IAccumulator.sol` | Adapted for module interface | Replace |
| `IAccumulatorFactory.sol` | *(eliminated)* | Remove |
| — | `MerkleValidator.sol` | New |

### Infrastructure Layer

| V1 | V2 | Action |
|---|---|---|
| Custom relayer (direct calls) | 4337 bundler + paymaster | Adapt relayer |
| `executeX` with Merkle proof | UserOps with Merkle proof in signature | New signing flow |
| Direct `executeIntent` call | UserOp targeting `executeIntent` | Route through EntryPoint |
| HMAC-based gas sponsorship | Paymaster contract | Deploy paymaster |

### Client Layer (SwiftUI)

| V1 | V2 | Action |
|---|---|---|
| Build `Call[]` + salt + proof | Build `PackedUserOperation` + proof | New UserOp builder |
| Sign `toEthSignedMessageHash(root)` | Sign Merkle root (same P-256) | Same signing, different leaf type |
| Send to relayer HTTP API | Send UserOps to bundler | New submission path |
| Track via custom events | Track via UserOp receipt + fill events | Adapt tracking |
| Balance display (simple) | Balance display + fill status | Read from AccumulatorModule |

## Migration Strategy

### Phase 1: Deploy V2 alongside V1

Deploy V2 modules to all target chains. Do not deactivate V1.

1. Deploy `MerkleValidator` singleton
2. Deploy `CrossChainExecutor` singleton
3. Deploy `AccumulatorModule` singleton
4. Deploy `KnotAccount` implementation
5. Deploy paymaster contract
6. Verify all contracts on block explorers

### Phase 2: New accounts use V2

New account creation (EIP-7702 delegation) points to `KnotAccount` instead of `UnifiedAccount`. The init UserOp installs all modules.

Existing V1 accounts continue operating on V1. No disruption.

### Phase 3: Migrate existing accounts

EIP-7702 allows re-delegation. Existing accounts can re-delegate to `KnotAccount`:

1. Complete all active V1 fills (wait for `executeIntent` or `markStale`)
2. Re-delegate EOA to `KnotAccount` implementation
3. Submit init UserOp to install modules (uses ECDSA fallback)
4. Account is now V2

**Important:** Any funds in the V1 `Accumulator` contract must be swept back to the account before migration. Once the account re-delegates, V1's `Accumulator.sweep()` still works (the account address is the owner).

### Phase 4: Decommission V1

Once all accounts have migrated and no V1 Accumulators hold funds:

1. V1 contracts remain deployed (immutable) but unused
2. Remove V1 code from active development
3. Relayer drops V1 support

## Account Re-delegation Flow

```
1. User initiates migration in app
2. App checks: any active V1 fills?
   - Yes → wait for completion or sweep
   - No → proceed
3. App sweeps V1 Accumulator if needed
4. EOA re-delegates to KnotAccount (EIP-7702 authorization)
5. App builds init UserOp:
   - Signs with EOA ECDSA key (bootstrap fallback)
   - Installs MerkleValidator with P-256 key
   - Installs CrossChainExecutor with spokePool
   - Installs AccumulatorModule with spokePool
   - Installs AccumulatorModule as fallback handler
6. Submit init UserOp via bundler
7. Account is V2 — all subsequent ops use MerkleValidator
```

## Rollback Plan

If V2 has issues after deployment:

- **New accounts:** Re-delegate back to `UnifiedAccount`. V1 code is still deployed.
- **Migrated accounts:** Re-delegate back to `UnifiedAccount`. Re-initialize V1 (deploy new Accumulator via factory).
- **Funds:** Always at the account address (EOA). Delegation changes don't affect token balances.

EIP-7702's re-delegation capability is the safety net. The account address never changes, so funds are never at risk.

## Risk Assessment

| Risk | Mitigation |
|---|---|
| V2 contract bug | Audit + testnet deployment + phased rollout |
| Bundler downtime | Fallback: direct ECDSA execution via EntryPoint (no modules needed for basic transfers) |
| Paymaster issues | User can self-fund gas (no paymaster in UserOp) |
| Migration interruption | V1 remains functional — user can continue using V1 |
| Active fills during migration | App enforces: complete all fills before migration |
| Destination intent no longer solvent | `AccumulatorModule.executeIntent` drops the fill instead of locking the account |

## Timeline

No fixed timeline. Migration begins when:

1. V2 contracts pass audit
2. UserOp lifecycle is implemented in SwiftUI
3. Bundler infrastructure is stable
4. Testnet validation is complete

V1 runs indefinitely until all conditions are met.

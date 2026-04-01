# Faucet V1

Faucet V1 is a one-shot, best-effort testnet funding system.

It is not a reusable entitlement and not a user-retryable workflow.

Once a faucet request is accepted for a user:

- the request is permanently consumed
- the descriptor is closed to future user requests
- backend infrastructure attempts funding asynchronously

This matches the product rule:

- whether funding later succeeds or fails, the user cannot issue the faucet request a second time

## Scope

Faucet V1 is intentionally small:

- fixed list of `3` supported testnets
- fixed list of `2` funded assets
- protocol-controlled funding only
- server-side execution only

Because the funding set is fixed and batched, Faucet V1 should use a protocol-owned smart account.

## Route

Faucet V1 should expose one app-facing route:

- `POST /v1/faucet/request`
  - allowed methods:
    - `knot_faucetRequest`

This route should use normal authenticated app access.

It does not need the same payload complexity as relay.

## Request Semantics

The user does not specify arbitrary funding calls.

The backend already knows:

- the supported chains
- the funded assets
- the funding amounts

So the request should stay lean:

- no arbitrary asset list
- no arbitrary chain list
- no client-defined transaction payloads

The route is just a request to consume the faucet entitlement.

## Lean Descriptor

Faucet V1 should use one lean descriptor row in D1.

Suggested table:

- `faucet_descriptors`

Suggested fields:

- `user_id` unique
- `status`
- `requested_at`
- `closed_at` nullable
- `tx_references` nullable

Suggested statuses:

- `accepted`
- `fulfilled`
- `closed`

Meaning:

- `accepted`
  - request consumed
  - work enqueued
  - not yet terminal
- `fulfilled`
  - funding completed successfully
  - closed permanently
- `closed`
  - funding closed without full success
  - closed permanently

`tx_references` should hold the small list of transaction references produced by the batched funding work.

No `job_id` is needed.
No separate failure reason column is needed.
If inspection is necessary later, the transaction references are the debugging surface.

## Why D1

D1 is the source of truth for faucet entitlement because this is authoritative business state:

- one user can request only once
- the closure is permanent
- support and ops must be able to inspect the descriptor

This should be enforced with a unique constraint on `user_id`.

## Durable Object Gate

Faucet V1 should use a per-user Durable Object for atomic acceptance.

The Faucet DO should:

1. receive the user request
2. check D1 for an existing descriptor
3. if one exists, reject the request
4. if none exists:
   - insert the descriptor as `accepted`
   - enqueue one funding job
5. return accepted

This DO is not the permanent source of truth.
It is the atomic gate that prevents:

- double insert
- double enqueue
- race conditions from concurrent requests

## Queue Execution

Funding itself should run asynchronously through a queue.

Suggested queue payload:

- `userId`

The queue worker can load the descriptor from D1 and derive the full funding plan from server config.

This keeps the payload lean and idempotent.

## Funding Execution

Because Faucet V1 needs batched multi-chain or multi-asset funding behavior, a protocol-owned smart account is justified.

The faucet executor should:

- be protocol-owned
- be server-side only
- use the existing Gelato execution rail
- batch the fixed funding calls

The client should never define or influence the actual call set beyond asking to consume the entitlement.

## Idempotency Model

Faucet V1 should have three layers of idempotency:

### 1. D1 uniqueness

`user_id` is unique in `faucet_descriptors`.

This is the hard entitlement lock.

### 2. Durable Object serialization

The DO serializes:

- existence check
- descriptor insert
- queue enqueue

### 3. Queue worker idempotency

The worker should re-read the descriptor from D1.

If it is already:

- `fulfilled`
- `closed`

the worker should no-op.

This protects against duplicate queue delivery.

## Completion Model

The funding worker should update the descriptor:

- to `fulfilled` if the funding batch completes successfully
- to `closed` if the funding batch is considered terminal but not fully successful

In both cases:

- `closed_at` is set
- `tx_references` is updated with the available transaction references

This keeps the descriptor terminal and small.

## Anomalies

If funding work fails in a way that requires operator awareness, the worker should emit an anomaly message through the independent anomaly queue.

The descriptor still remains closed.

That means anomaly handling is operational only.
It does not reopen the faucet entitlement.

## Why This Is Lean

Faucet V1 should not become a general funding workflow engine.

It only needs:

- one app route
- one durable descriptor
- one per-user atomic gate
- one queue worker
- one protocol-owned smart account

That is enough to be correct and robust.

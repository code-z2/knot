# Relay V1

Relay V1 is a sponsored-only `UserOperation` relay surface.

It exists for two cases:

- app-initiated sponsored relay
- rooted multi-step relay plans that include immediate, background, and deferred `UserOperation`s

The route should stay narrow:

- `POST /v1/relay/submit`
- route-scoped RPC envelope
- strict Zod validation at the boundary
- provider-native `UserOperation` payloads

This endpoint is not a generic bundler proxy for every payment mode.
Non-sponsored flows should go through the app directly.

## Scope

Relay V1 should accept only sponsored traffic.

That means:

- payment mode is always `sponsored`
- relay proxy is responsible for sending to Gelato's sponsored bundler path
- non-sponsored `native` or `erc20` payment flows are out of scope for this endpoint

Relay V1 should also keep queueing narrow:

- `immediate` is sent inline
- `background` is sent inline after `immediate`
- only `deferred` is queued

## Route

- `POST /v1/relay/submit`
  - allowed methods:
    - `knot_relaySubmit`

This route should use high-fidelity auth.

## Why UserOperation-Native

The old relay shape was transaction-native:

- `immediateTxs`
- `backgroundTxs`
- `deferredTxs`

Relay V1 should speak `UserOperation`s instead.

That makes the contract cleaner because:

- validation gets simpler
- payloads stay close to Gelato
- the proxy does not need to reinterpret wallet-level transaction intent
- the same `UserOperation` can be validated, simulated, stored, and passed through

## Rooted Execution Model

The relay root still has three phases:

- `immediate`
- `background`
- `deferred`

They are not three unrelated products.
They are one rooted execution plan.

### Immediate

`immediate` is a single sponsored `UserOperation`.

Its purpose is typically:

- destination account bootstrap
- destination deployment
- any first required synchronous step before the rest of the plan

It should be submitted through the synchronous Gelato path first.

### Background

`background` is a list of sponsored `UserOperation`s.

It should run only after `immediate` succeeds.

These are still part of the same rooted user flow, but they do not need the same synchronous UX boundary as the bootstrap step.
They are still sent inline during the same request lifecycle.

### Deferred

`deferred` is a single sponsored `UserOperation`.

This is the stored later `executeIntent` operation.

It is not submitted during the initial relay request.
It is stored with a TTL and later resolved by `fillId` when Goldsky sees the hub ready event.
Deferred execution is the only relay phase that should enter the queue pipeline.

## Request Shape

Relay V1 should use a discriminated union for `params`.

### Single

For normal one-shot sponsored relay:

```json
{
  "jsonrpc": "2.0",
  "method": "knot_relaySubmit",
  "params": {
    "kind": "single",
    "chainId": 8453,
    "params": [
      {
        "sender": "0x...",
        "nonce": "0x...",
        "callData": "0x...",
        "signature": "0x...",
        "maxFeePerGas": "0x0",
        "maxPriorityFeePerGas": "0x0"
      },
        "0x0000000071727De22E5E9d8BAf0edAc6f37da032"
    ]
  },
  "id": "req_123"
}
```

### Plan

For rooted multi-step relay:

```json
{
  "jsonrpc": "2.0",
  "method": "knot_relaySubmit",
  "params": {
    "kind": "plan",
    "chainId": 8453,
    "fillId": "0x...",
    "params": [
      {
        "immediate": {
          "sender": "0x...",
          "nonce": "0x...",
          "callData": "0x...",
          "signature": "0x...",
          "maxFeePerGas": "0x0",
          "maxPriorityFeePerGas": "0x0"
        },
        "background": [
          {
            "sender": "0x...",
            "nonce": "0x...",
            "callData": "0x...",
            "signature": "0x...",
            "maxFeePerGas": "0x0",
            "maxPriorityFeePerGas": "0x0"
          }
        ],
        "deferred": {
          "sender": "0x...",
          "nonce": "0x...",
          "callData": "0x...",
          "signature": "0x...",
          "maxFeePerGas": "0x0",
          "maxPriorityFeePerGas": "0x0"
        }
      },
      "0x0000000071727De22E5E9d8BAf0edAc6f37da032"
    ]
  },
  "id": "req_123"
}
```

## Validation Rules

Validation should happen at the Zod boundary.

Do not normalize or sanitize relay payloads.

Strict rules:

- `jsonrpc` must be `2.0`
- `method` must be `knot_relaySubmit`
- `kind` must be `single` or `plan`
- `chainId` must be an integer
- `entryPoint` must be a valid address
- every `UserOperation.sender` must equal `session.userId`
- every `UserOperation` must be structurally valid
- `plan.fillId` is required when `kind = plan`
- `plan` must contain at least one of:
  - `immediate`
  - non-empty `background`
  - `deferred`

### Sponsored-only rule

The endpoint should reject any request that does not match Gelato's sponsored settlement assumptions.

Important Gelato rule:

> When using Gelato Bundler for sponsoring transactions with Gas Tank, both `maxFeePerGas` and `maxPriorityFeePerGas` are set to `0`. This allows fees to be settled post-execution instead of upfront via the EntryPoint.

So Relay V1 should enforce:

- `maxFeePerGas === 0`
- `maxPriorityFeePerGas === 0`

on every incoming `UserOperation`.

This route should not silently rewrite those fields.
If the client sends the wrong fee shape, reject the request.

## Chain Policy Validation

`chainId` validation should be split into two layers.

### Schema boundary

Zod should validate only structural correctness:

- `chainId` exists
- `chainId` is an integer

### Runtime policy boundary

A dedicated route guard or middleware should validate:

- the `chainId` is supported by Knot
- the `chainId` is enabled in the current environment
- a Goldsky RPC URL can be derived for the `chainId`
- a Gelato bundler URL can be derived for the `chainId`
- a quote token address can be derived for the `chainId`
- the provided `entryPoint` belongs to the supported entry point set for that `chainId`

This keeps responsibilities clean:

- schema validates payload shape
- runtime policy validates environment support

Do not hard-code this into a broad parser or silent normalization layer.

## Entry Point Policy

Relay V1 should not force one singular hard-coded entry point across all clients if the backend legitimately supports more than one.

The client may send its chosen `entryPoint`.

Backend policy should then validate:

- the `entryPoint` is structurally valid
- the `entryPoint` is supported for the selected `chainId`

So the internal chain config should expose:

- `supportedEntryPoints: readonly Address[]`

instead of one mandatory single `entryPoint` field.

This keeps the client flexible while still preserving chain-level backend policy.

## Quote Middleware

Relay V1 should use a dedicated quote middleware or helper after chain policy validation.

That quote layer should:

- derive the per-chain quote token from chain config
- call Gelato quote endpoints for `single`, `immediate`, and `background`
- attach estimated sponsored fee inputs for reservation creation

Relay V1 should not trust client-provided fee assumptions as the reservation source of truth.

The client may still estimate locally for UX, but reservation should be based on backend-derived quote inputs.

## Simulation Policy

Relay V1 should simulate only:

- `single`
- `plan.immediate`
- `plan.background`

Relay V1 should not simulate:

- `plan.deferred`

Reason:

- immediate and background are executed now
- deferred executes against future state
- meaningful deferred simulation would push the backend into brittle future-state assumptions and complex state overrides

So the rule is:

- structurally validate deferred
- store deferred with TTL
- execute deferred only when Goldsky later wakes it up by `fillId`

The client is still responsible for producing a valid rooted plan.
Relay V1 simulation is only a bounded safety layer for what is executed now.

## Storage Model

Only deferred needs storage.

There is no need for a durable relay-plan table in V1 if the rooted plan itself does not need later recovery.

Recommended storage:

- dedicated `DEFERRED_RELAY_KV`
- key:
  - `deferred-userop:{fillId}`
- value:
  - serialized object containing:
    - `fillId`
    - `userId`
    - `chainId`
    - `entryPoint`
    - `userOperation`
    - `createdAt`
    - `expiresAt`

Use KV TTL for automatic expiry, but also store `expiresAt` inside the value and re-check on read.

Relay V1 does not need a durable relay-plan table in V1.
Immediate and background are sent inline and do not need long-lived recovery storage.

## Gas Tank Model

Relay V1 should target post-transaction settlement instead of optimistic pre-debit.

The intended model is:

- gas tank settles in Base USDC only
- relay proxy charges from the current server-side Gelato quote for the accepted relay request
- debit happens after execution, not before

That means gas tank is an accounting and settlement layer, not a quote-time payload mutation layer.

If an admission control check exists, it should be lightweight and separate from final debit.

Reservation creation should happen after the relay send has a real quote or task context, not from raw incoming fee fields.

## Goldsky Integration

Goldsky only cares about deferred.

The later flow is:

1. initial relay plan stores `deferred` in `DEFERRED_RELAY_KV`
2. `KnotConsumerHub` emits `FillReady(fillId)`
3. Goldsky sees `FillReady(fillId)`
4. Goldsky calls the narrow deferred relay path with `fillId`
5. relay proxy resolves `deferred-userop:{fillId}`
6. relay proxy submits that `UserOperation` to Gelato

This keeps Goldsky orchestration keyed by `fillId` while relay-proxy remains the execution glue.

## Queue Boundary

Relay V1 should not queue immediate or background execution.

The queue boundary is:

- deferred relay execution
- reservation settlement
- anomaly notification delivery

This keeps the route surface predictable and prevents the queue model from leaking into normal user relay.

## RPC Routing

Relay V1 should stay on the route-scoped RPC model:

- route defines the subsystem
- method defines the exact action
- payload stays provider-shaped where that reduces mental overhead

This means the relay proxy should not invent a large normalization layer around `UserOperation`s.

## Next Step

After this route exists, the next architecture pass should define:

- the deferred execution route Goldsky will call by `fillId`
- the simulator service boundary
- the post-execution gas tank settlement contract

That follow-up architecture now lives in:

- [06-gas-tank-v1.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/06-gas-tank-v1.md)
- [07-queues-anomalies.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/07-queues-anomalies.md)
- [08-storage-model.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/08-storage-model.md)

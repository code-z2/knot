# Relay Proxy Overview

The relay proxy is a narrow edge backend for Knot.

It should stay:
- small
- explicit
- Cloudflare-native
- strict at the API boundary

The backend should use:
- `Hono`
- `Cloudflare Workers`
- route-scoped RPC envelopes
- uniform app-facing auth

The relay proxy sits between:
- the iOS app
- Goldsky-driven orchestration
- Gelato relay, bundler, and paymaster APIs
- storage providers such as Pinata

Operationally, Relay Proxy V1 also depends on:

- a dedicated deferred relay KV
- a reservation Durable Object domain
- a faucet Durable Object domain
- queue workers for deferred relay, debit settlement, and anomaly delivery
- D1 for durable policy state
- KV daily buckets for rolling gas usage aggregates

## Design Direction

The public API should not be a generic JSON-RPC endpoint.

It should also not be a loose REST API with provider-specific ad hoc bodies.

Instead, Knot should use route-scoped RPC:
- the route defines the subsystem boundary
- the body carries a strict JSON-RPC-style envelope
- each route accepts an explicit allowlist of methods

Example:
- `POST /v1/user/login/options`
- body method: `knot_userLoginOptions`

- `POST /v1/upload/image/options`
- body method: `knot_imageUploadOptions`

- `POST /v1/relay/submit`
- body method: `knot_relaySubmit`

- `POST /v1/faucet/request`
- body method: `knot_faucetRequest`

- `POST /v1/chains`
- body method: `knot_supportedChains`

This keeps:
- Hono middleware clean
- method contracts strict
- provider-native relay payloads close to upstream shape

## Core Rules

- App-facing routes use one auth contract.
- Route-method matching is explicit and allowlisted.
- Relay routes may preserve provider-native params when that reduces adapter churn.
- The top-level request envelope still belongs to Knot, not to the provider.
- Health and operational routes may remain plain JSON.
- Only deferred execution is queued in Relay V1.
- Reservations are operational state, not permanent business records.
- Onchain GasTank balance is the safety source for final settlement and overdraft checks.

## Operational Components

Relay Proxy V1 should be understood as six bounded parts:

- user-facing routes
- internal operational routes
- Gelato client and quote helpers
- Gas Tank reservation and settlement pipeline
- queue workers
- storage bindings

The user-facing route surface should stay small.

The internal operational surface should stay narrower still.
It exists for:

- Goldsky-triggered deferred execution
- queue-driven settlement
- health and operational checks

## Initial Barebones

The first scaffold only needs:
- `GET /`
- `GET /health`
- `POST /v1/user/register/options`
- `POST /v1/user/register/verify`
- `POST /v1/user/login/options`
- `POST /v1/user/login/verify`
- `POST /v1/user/logout`
- `POST /v1/upload/image/options`
- `POST /v1/relay/submit`

The RPC routes should validate:
- `jsonrpc`
- `method`
- route-method compatibility
- presence and shape of `params`

Passkeys, App Attest, D1, and KV now layer on top of this contract.

See also:

- [05-relay-v1.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/05-relay-v1.md)
- [06-gas-tank-v1.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/06-gas-tank-v1.md)
- [07-queues-anomalies.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/07-queues-anomalies.md)
- [08-storage-model.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/08-storage-model.md)
- [09-faucet-v1.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/09-faucet-v1.md)
- [10-chain-list-v1.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/10-chain-list-v1.md)

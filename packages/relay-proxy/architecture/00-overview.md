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

The RPC routes should validate:
- `jsonrpc`
- `method`
- route-method compatibility
- presence and shape of `params`

Passkeys, App Attest, D1, and KV now layer on top of this contract.

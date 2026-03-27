# Relay Proxy Auth

The relay proxy should treat the iOS app as a public client.

Do not rely on:
- static bearer tokens embedded in the app
- HMAC secrets embedded in the app

Those are not durable trust boundaries for a shipped mobile client.

## Auth Shape

Knot should use:
- passkeys for user authentication
- Apple App Attest for app and device attestation
- short-lived backend sessions
- one uniform auth middleware for app-facing routes
- `D1` for durable auth state
- `KV` for one-time challenges and nonces

The route-scoped RPC API does not change that model.

It only changes the request body contract:
- route defines the subsystem
- RPC method defines the exact command

Auth still wraps the route, not the method family.

## Uniform App-Facing Contract

All authenticated app-facing RPC routes should require the same boundary:
- session token
- App Attest key binding
- nonce
- timestamp
- request hash
- App Attest assertion

Do not split app routes into separate auth classes just because one route is a session route and another is a relay route.

The only separate trust boundary should be true non-app actors such as:
- internal workers
- admin callbacks
- provider webhooks, if any are introduced later

## Hono Fit

`Hono` is a good fit because auth can live in middleware while the handlers stay small.

The clean shape is:
- route-level middleware for auth
- route-level middleware for RPC envelope validation
- small handlers with strict typed params

Example:

```ts
app.post('/v1/user/login/begin', rpcMethod('knot_userLoginBegin'), async (c) => {
  const request = c.get('rpc')

  return c.json({
    jsonrpc: '2.0',
    id: request.id,
    result: {
      ok: true,
    },
  })
})
```

Auth middleware then sits before the handler:

```ts
app.post('/v1/relay/submit', appAuth, rpcMethod('eth_sendUserOperation'), async (c) => {
  const request = c.get('rpc')
  return c.json({
    jsonrpc: '2.0',
    id: request.id,
    result: {
      accepted: true,
      method: request.method,
    },
  })
})
```

## Why This Is Clean

- routes remain readable for humans
- methods remain strict for machines
- auth does not need special cases per command family
- the backend can stay close to Gelato payload shapes without exposing a generic passthrough endpoint

## Current Implementation

The active relay proxy now uses:
- `webauthx/server` for passkey registration and authentication options plus verification
- `node-app-attest` for App Attest attestation and assertion verification
- `D1` for:
  - `users`
  - `app_attestations`
  - `sessions`
- `KV` for:
  - one-time begin/finish challenges
  - replay nonces

Cloudflare secrets should hold:
- `KNOT_RP_ID`
- `KNOT_RP_NAME`
- `KNOT_RP_ORIGIN`
- `KNOT_APPLE_BUNDLE_ID`
- `KNOT_APPLE_TEAM_ID`
- `KNOT_APP_ATTEST_ALLOW_DEVELOPMENT`

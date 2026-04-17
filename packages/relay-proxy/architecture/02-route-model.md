# Relay Proxy Route Model

The relay proxy should use route-scoped RPC.

That means:
- route path defines the subsystem boundary
- request body uses a JSON-RPC-style envelope
- each route accepts only an explicit allowlist of methods

## Envelope

```json
{
  "jsonrpc": "2.0",
  "method": "knot_userLoginOptions",
  "params": {
    "credentialId": "credential_123"
  },
  "id": "req_123"
}
```

The backend should own this envelope shape even when relay params stay close to Gelato.

## Initial Routes

- `POST /v1/user/register/options`
  - allowed methods:
    - `knot_userRegisterOptions`

- `POST /v1/user/register/verify`
  - allowed methods:
    - `knot_userRegisterVerify`

- `POST /v1/user/login/options`
  - allowed methods:
    - `knot_userLoginOptions`

- `POST /v1/user/login/verify`
  - allowed methods:
    - `knot_userLoginVerify`

- `POST /v1/user/logout`
  - allowed methods:
    - `knot_userLogout`

- `POST /v1/upload/image/options`
  - allowed methods:
    - `knot_imageUploadOptions`

- `POST /v1/relay/submit`
  - allowed methods:
    - `knot_relaySubmit`

- `POST /v1/faucet/request`
  - allowed methods:
    - `knot_faucetRequest`

- `POST /v1/chains`
  - allowed methods:
    - `knot_supportedChains`

- `POST /v1/profile`
  - allowed methods:
    - `knot_profileUpdate`

- `POST /v1/gas/withdraw`
  - allowed methods:
    - `knot_gasWithdraw`

Operational routes may stay plain JSON:
- `GET /`
- `GET /health`

Public read routes may also stay plain JSON or plain HTTP:

- `GET /ccip/ens/{sender}/{data}.json`
- `GET /public/profile/reverse?address=0x...`
- `GET /public/profile/name?name=pizza.not.fi`

Internal operational routes should be kept separate from user-facing routes.

Examples:

- Goldsky-triggered deferred execution route
- queue or cron-driven settlement hooks
- operational health or admin routes

These routes should not share the same assumptions as app-facing routes just because they live in the same Worker.

## Validation Rule

Do not infer allowed methods from a regex alone.

Use an explicit route-to-method map as the trust boundary:

```ts
const ROUTE_METHODS = {
  '/v1/user/register/options': ['knot_userRegisterOptions'],
  '/v1/user/register/verify': ['knot_userRegisterVerify'],
  '/v1/user/login/options': ['knot_userLoginOptions'],
  '/v1/user/login/verify': ['knot_userLoginVerify'],
  '/v1/user/logout': ['knot_userLogout'],
  '/v1/upload/image/options': ['knot_imageUploadOptions'],
  '/v1/relay/submit': ['knot_relaySubmit'],
  '/v1/faucet/request': ['knot_faucetRequest'],
  '/v1/chains': ['knot_supportedChains'],
  '/v1/profile': ['knot_profileUpdate'],
  '/v1/gas/withdraw': ['knot_gasWithdraw'],
} as const
```

Optional naming rules may exist, but they are secondary.

## Hono Shape

```ts
app.post('/v1/user/login/options', rpcMethod('knot_userLoginOptions'), handleUserLoginOptions)
app.post('/v1/upload/image/options', rpcMethod('knot_imageUploadOptions'), handleImageUploadOptions)
app.post('/v1/relay/submit', rpcMethod('knot_relaySubmit'), handleRelaySubmit)
app.post('/v1/faucet/request', rpcMethod('knot_faucetRequest'), handleFaucetRequest)
app.post('/v1/chains', rpcMethod('knot_supportedChains'), handleChainList)
app.post('/v1/profile', rpcMethod('knot_profileUpdate'), handleProfileUpdate)
app.post('/v1/gas/withdraw', rpcMethod('knot_gasWithdraw'), handleGasWithdraw)
```

The `rpcMethod(...)` middleware should:
- parse JSON
- validate `jsonrpc === "2.0"`
- validate `method`
- validate route-method compatibility
- expose the typed request on the context

## Error Shape

The CCIP route is the exception.

It should not use the JSON-RPC envelope because ENS resolvers expect a plain HTTP gateway.

It should return:

```json
{
  "data": "0x..."
}
```

This route is infrastructure, not an app-facing RPC route.

Invalid RPC requests should return JSON-RPC-style errors.

Example:

```json
{
  "jsonrpc": "2.0",
  "id": "req_123",
  "error": {
    "code": -32600,
    "message": "invalid_request"
  }
}
```

This keeps the route contract strict and easy to test.

## Gas Withdrawal Semantics

`POST /v1/gas/withdraw` is the fast-path withdrawal route.

The intended behavior is:

1. authenticate the user
2. read the user's Base Gas Tank balance and durable outstanding debt
3. collect `min(balance, outstandingDebt)` from the Gas Tank
4. reject if outstanding debt remains after collection
5. compute the withdraw amount as the remaining debt-free Gas Tank balance
6. reject if the computed withdraw amount is zero
7. reject if current policy still blocks fast withdrawal
8. read the current Gas Tank withdraw nonce
9. return the computed amount and protocol cosigner signature for immediate owner withdrawal

Permissionless delayed withdrawal remains an onchain escape hatch and does not require the relay proxy.

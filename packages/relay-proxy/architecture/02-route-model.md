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

Operational routes may stay plain JSON:
- `GET /`
- `GET /health`

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
} as const
```

Optional naming rules may exist, but they are secondary.

## Hono Shape

```ts
app.post('/v1/user/login/options', rpcMethod('knot_userLoginOptions'), handleUserLoginOptions)
app.post('/v1/upload/image/options', rpcMethod('knot_imageUploadOptions'), handleImageUploadOptions)
```

The `rpcMethod(...)` middleware should:
- parse JSON
- validate `jsonrpc === "2.0"`
- validate `method`
- validate route-method compatibility
- expose the typed request on the context

## Error Shape

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

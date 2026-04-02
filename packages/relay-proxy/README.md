# relay-proxy

Route-scoped JSON-RPC edge backend for Knot on `Hono + Cloudflare Workers`.

It currently owns:
- passkey + App Attest auth
- supported chains discovery
- sponsored relay submission
- direct image upload option issuance
- deferred intent-execution queueing
- anomaly delivery workers

Architecture docs live in [architecture/README.md](/Users/peter/Developer/knot/packages/relay-proxy/architecture/README.md).

## Endpoints

- `GET /`
- `GET /health`
- `POST /v1/user/register/options`
  - method: `knot_userRegisterOptions`
- `POST /v1/user/register/verify`
  - method: `knot_userRegisterVerify`
- `POST /v1/user/login/options`
  - method: `knot_userLoginOptions`
- `POST /v1/user/login/verify`
  - method: `knot_userLoginVerify`
- `POST /v1/user/logout`
  - method: `knot_userLogout`
- `POST /v1/chains`
  - method: `knot_supportedChains`
- `POST /v1/relay/submit`
  - method: `knot_relaySubmit`
- `POST /v1/upload/image/options`
  - method: `knot_imageUploadOptions`

The root `GET /` response exposes the current `supportedMethods` list.

## Implemented Surface

### Auth

Implemented now:
- begin/finish user registration with `webauthx`
- begin/finish user login with `webauthx`
- Apple App Attest attestation verification
- per-request App Attest assertion verification for high-fidelity routes
- opaque access and refresh token issuance
- low/high auth fidelity middleware
- D1-backed durable auth records
- KV-backed one-time challenges and replay nonces

### Chains

Implemented now:
- strict supported chain registry with explicit `mainnet` / `testnet` split
- supported entry point validation
- public `knot_supportedChains` route
- Goldsky JSON-RPC URL builder
- Gelato bundler URL builder

### Relay

Implemented now:
- sponsored-only `knot_relaySubmit`
- strict `UserOperation`-native request validation
- high-fidelity auth on relay submission
- sender must match `session.userId`
- inline `single` relay submission
- inline `plan.immediate` sync submission
- inline `plan.background` submission
- deferred `plan.deferred` persistence and queue dispatch by `fillId`

Not implemented yet:
- gas tank reservation / settlement pipeline
- relay status route
- Goldsky-triggered operational execution route

### Upload

Implemented now:
- signed Pinata image upload option issuance
- low-fidelity authenticated access
- strict filename/content-type validation at the schema boundary

### Workers

Implemented now:
- anomaly queue worker
- intent-execution queue worker
- scheduled intent-execution sweep / retry path

## Runtime Shape

### Route and Middleware Layout

- `src/routes`
- `src/middleware`
- `src/services`
- `src/stores`
- `src/types`
- `src/utils`
- `src/workers`
- `tests`

### Storage

Current implemented storage:
- `AUTH_DB`
  - D1 for auth state
- `AUTH_KV`
  - one-time challenges and nonce replay tombstones
- `RELAY_KV`
  - deferred intent-execution records

### Queues

Current implemented queues:
- `RELAY_QUEUE`
  - deferred intent-execution dispatch
- `ANOMALY_QUEUE`
  - operator anomaly delivery

### Secrets / Bindings

Current runtime bindings:
- `AUTH_DB`
- `AUTH_KV`
- `RELAY_KV`
- `RELAY_QUEUE`
- `ANOMALY_QUEUE`
- `BUNDLER_API_KEY`
- `JSON_RPC_API_KEY`
- `DISCORD_WEBHOOK_URL`
- `KNOT_RP_ID`
- `KNOT_RP_NAME`
- `KNOT_RP_ORIGIN`
- `KNOT_APPLE_BUNDLE_ID`
- `KNOT_APPLE_TEAM_ID`
- `KNOT_APP_ATTEST_ALLOW_DEVELOPMENT`
- `PINATA_JWT`
- `PINATA_GATEWAY_BASE_URL`
- `PINATA_IMAGE_GROUP_ID`
- `PINATA_MAX_FILE_SIZE_BYTES`
- `PINATA_SIGN_EXPIRES_SECONDS`

Provision secrets with Cloudflare secrets, not plain `vars`.

## Migrations

Current D1 schema baseline:
- [0001_auth.sql](/Users/peter/Developer/knot/packages/relay-proxy/migrations/0001_auth.sql)

Current tables:
- `users`
- `passkeys`
- `app_attestations`
- `sessions`

## Scripts

- `bun run dev`
- `bun run build`
- `bun run check`
- `bun run test`
- `bun run verify`

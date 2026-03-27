# relay-proxy

Barebones `Hono + Cloudflare Workers` relay proxy scaffold with route-scoped RPC envelopes.

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
- `POST /v1/upload/image/options`
  - method: `knot_imageUploadOptions`

## Structure

- `src/stores`
- `src/services`
- `src/routes`
- `src/middleware`
- `src/types`
- `src/utils`
- `tests`

## Current Auth Slice

Implemented now:
- begin and finish user registration with real `webauthx` registration options and verification
- begin and finish user login with real `webauthx` authentication options and verification
- real Apple App Attest verification with `node-app-attest`
- opaque access and refresh token issuance
- attestation-key-bound relay auth
- per-request App Attest assertion verification
- D1-backed users, sessions, and App Attest key state
- KV-backed one-time challenges and nonces
- signed image upload URL issuance for direct-to-Pinata uploads

## Cloudflare Bindings

Storage bindings:
- `AUTH_DB` as D1
- `AUTH_KV` as KV

Secrets:
- `KNOT_RP_ID`
- `KNOT_RP_NAME`
- `KNOT_RP_ORIGIN`
- `KNOT_APPLE_BUNDLE_ID`
- `KNOT_APPLE_TEAM_ID`
- `KNOT_APP_ATTEST_ALLOW_DEVELOPMENT`
- `PINATA_JWT`
- `PINATA_GATEWAY_BASE_URL`
- `PINATA_IMAGE_GROUP_ID`

These should be provisioned with Cloudflare secrets, not plain `vars` in `wrangler.toml`.

## Data Model

D1 schema lives in:
- `migrations/0001_auth.sql`

Tables:
- `users`
- `app_attestations`
- `sessions`

## Scripts

- `bun run dev`
- `bun run build`
- `bun run check`
- `bun test`
- `bun run verify`

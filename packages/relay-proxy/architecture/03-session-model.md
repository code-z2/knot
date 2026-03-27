# Relay Proxy Session Model

## Status

Draft.

## Goal

Define the backend session contract used after:

- App Attest verification
- passkey user authentication

## Session Shape

Use:

- opaque access token
- opaque refresh token

Do not use a long-lived client secret.

JWTs are possible, but opaque tokens are the cleaner first choice for this service because:

- revocation is simpler
- device binding is explicit
- there is less temptation to trust client-visible claims

## Token Lifetimes

Recommended defaults:

- access token: `5 to 15 minutes`
- refresh token: longer-lived, revocable, device-bound

The refresh token should be stored in the iOS Keychain.

## Session Binding

A session should bind at minimum:

- `sessionId`
- `userId`
- `appAttestKeyId`
- `issuedAt`
- `expiresAt`
- `status`

## Suggested Records

```ts
type SessionRecord = {
  id: string
  userId: string
  accessToken: string
  refreshToken: string
  appAttestKeyId: string
  issuedAt: number
  expiresAt: number
  status: 'active' | 'revoked' | 'expired'
}
```

```ts
type AppAttestationRecord = {
  keyId: string
  publicKey: string
  signCount: number
  environment: 'development' | 'production'
  createdAt: number
  updatedAt: number
  status: 'active' | 'revoked'
}
```

## Nonce Model

Every app-facing request should carry a nonce.

Nonce record should bind:

- `appAttestKeyId`
- `nonce`
- short TTL

Recommended behavior:

- one-time use
- very short validity window
- reject replays immediately

## Request Challenge Binding

Every app-facing request should be tied to:

```text
method || path || sha256(body) || nonce || timestamp
```

The App Attest assertion should prove that exact challenge.

This means a stolen access token alone is not enough to replay backend calls.

## Login Flow

### 1. User Register or User Login

Backend issues one begin/finish challenge.

That one-time challenge is used for:
- `webauthx` passkey registration or authentication
- App Attest attestation or assertion

Backend verifies both and issues:

- access token
- refresh token

### 2. Authenticated App Request

Client sends:

- bearer access token
- `appAttestKeyId`
- nonce
- timestamp
- App Attest assertion

Backend verifies:

- session validity
- session-attestation-key binding
- nonce
- assertion

## Refresh Flow

Refresh should require:

- refresh token
- attestation-key binding
- active attestation record

Recommended first version:

- refresh also requires App Attest assertion

That keeps the auth model uniform and avoids a cheaper refresh lane.

## Revocation

The backend should be able to revoke:

- single session
- all sessions for one App Attest key
- all devices for one user

Revocation triggers may include:

- suspicious behavior
- manual logout
- device replacement
- attestation or passkey mismatch

## Hono Service Fit

Suggested service split:

- `passkey.service.ts`
  - begin and finish register/login
- `app-attest.service.ts`
  - verify attestation and assertion
- `session.service.ts`
  - issue, verify, refresh, revoke
- `nonce.service.ts`
  - issue and consume nonces

This keeps middleware small and stateful logic in services.

## First Implementation Rule

Do not over-design the session model.

First version only needs:

- device-bound opaque sessions
- short access token lifetime
- refresh token
- nonce consumption
- explicit revocation

That is enough to replace the old static app-secret model cleanly.

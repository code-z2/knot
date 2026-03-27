# Upload V1

Upload V1 should stay narrow.

It is not a general file service.

It should only solve:
- direct image upload from the iOS app
- short-lived signed upload URLs
- stable image identifiers that Knot controls
- clean integration with Pinata

## Why V1 Exists

The old upload flow already had the right high-level shape:
- client asks backend for a signed upload URL
- client uploads directly to Pinata
- backend does not proxy file bytes

That shape should remain.

What should improve in V1:
- fit the current `Hono + route-scoped RPC` backend
- stop treating upload as a one-off sidecar route outside the new auth system
- derive upload ownership and object identity server-side
- keep validation strict and image-only

## Scope

V1 should support:
- avatar uploads
- profile or account images if Knot needs them shortly after

V1 should not support yet:
- arbitrary file uploads
- video
- multi-part upload orchestration
- server-side image processing
- upload-complete webhooks
- metadata indexing in D1

That can come later if the product actually needs it.

## Route

Use one route-scoped RPC endpoint:

- `POST /v1/upload/image/options`
  - allowed method:
    - `knot_imageUploadOptions`

This keeps upload aligned with the current relay-proxy contract style instead of bringing back the old plain JSON island.

## Auth

Upload should use authenticated app routes.

For V1:
- require a valid session token
- use `low` auth fidelity by default

Reason:
- upload URL issuance is authenticated user activity
- but it is not as sensitive as relay submission
- the client may call it often during profile editing flows

If abuse shows up later, this route can be moved to `high` fidelity without changing the storage model.

## Request Shape

```json
{
  "jsonrpc": "2.0",
  "id": "upload_123",
  "method": "knot_imageUploadOptions",
  "params": {
    "purpose": "avatar",
    "fileName": "profile.jpg",
    "contentType": "image/jpeg",
    "byteLength": 182311
  }
}
```

### Request Rules

- `purpose` is an allowlisted string
- `fileName` is client input, but only used after server sanitization
- `contentType` must start with `image/`
- `byteLength` must be present and bounded

V1 should not trust a client-supplied `imageID`.

V1 should also not require the client to send a raw account address just to namespace storage.

The backend already has an authenticated session and should derive ownership from that session.

## Ownership Model

The upload owner should come from the authenticated session:
- `session.userId`

If a future feature needs an image to attach to a specific account address, that should be an explicit additional field with explicit validation.

But V1 should not start by trusting:
- `eoaAddress`
- `owner`
- `imageID`

from the client when those values can be derived or controlled server-side.

## Image ID

The backend should generate the image identifier.

Example shape:

```text
images/avatar/<userId>/<timestamp>-<random>-<sanitizedFileName>
```

Properties:
- deterministic namespace
- opaque enough for storage
- easy to log and debug
- not chosen by the client

The exact format is less important than the rule:
- the backend owns image identity

## Pinata Flow

The backend should ask Pinata for a signed upload URL with:
- short expiry
- file size limit
- file name
- group id
- server-owned keyvalues

Suggested Pinata keyvalues:
- `userId`
- `imageID`
- `purpose`
- `source = knot-relay`

If support-mode-specific grouping is still needed later, keep that as a backend routing concern, not a free-form client field.

## Response Shape

```json
{
  "jsonrpc": "2.0",
  "id": "upload_123",
  "result": {
    "uploadURL": "https://uploads.pinata.cloud/...",
    "imageID": "images/avatar/user_123/20260327...-profile.jpg",
    "gatewayBaseURL": "https://<gateway-host>/ipfs",
    "expiresAt": 1770000000000
  }
}
```

`imageID` is Knot's identifier.

The eventual CID comes from the upload itself, not from the options call.

## Validation Rules

V1 should reject:
- non-image content types
- empty file names
- oversized files
- unsupported purposes

The backend should sanitize:
- file name

The backend should bound:
- signed URL expiry
- max file size

These values should come from backend config, not from client input.

## Storage Model

V1 does not need D1 persistence for uploads.

That means:
- no `uploads` table yet
- no upload status row yet
- no webhook reconciliation yet

The backend only issues a signed upload URL and returns the server-generated `imageID`.

If Knot later needs auditability or upload completion tracking, that should be a V2 concern.

## Failure Model

If Pinata signed URL generation fails:
- return a typed RPC failure
- do not create partial server state

This route should remain stateless in V1.

## Suggested File Shape

When implemented, keep it small:

- `src/routes/upload.ts`
- `src/services/upload.ts`
- `src/services/pinata.ts`
- `src/types/upload.ts`

Avoid scattering upload logic across unrelated auth or relay files.

## V1 Summary

Upload V1 should be:
- direct-to-Pinata
- signed URL only
- image-only
- session-authenticated
- stateless on the backend
- server-owned for `imageID` and ownership metadata

That keeps it useful without turning relay-proxy into a generic media backend too early.

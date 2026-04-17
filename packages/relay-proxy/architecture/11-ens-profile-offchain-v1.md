# ENS Profile Offchain V1

Knot should move profile identity away from `.eth` commit/reveal and onchain text-record management.

The better product model is:

- branded ENS subdomains under `not.fi`
- ENS CCIP-Read for forward resolution
- backend-owned profile records
- gasless profile creation and editing
- app-managed reverse lookup through a public backend route

This keeps ENS as the naming and resolution facade while the backend becomes the real profile system.

## Product Direction

The profile system should support:

- `name -> address` resolution through ENS
- `address -> profile` reverse lookup through Knot
- gasless profile updates
- cheap reads
- deterministic public resolution

The profile system should not require:

- commit/reveal in the app
- per-user onchain registration costs
- onchain text-record writes for avatar or bio
- reverse ENS lookup

## High-Level Shape

The system should have four parts:

- ENS offchain resolver contract
- public CCIP gateway
- authenticated profile management API
- profile storage and public read indexes

### ENS contract layer

Knot should claim `not.fi` into ENS once.

After that:

- deploy ENS `OffchainResolver.sol`
- set the `not.fi` resolver to that contract
- configure the contract with:
  - the CCIP gateway URL template
  - the trusted signer address

The contract remains generic ENS infrastructure.
It should not contain app-specific profile logic.

## Resolution Flow

Forward resolution for `pizza.not.fi` should be:

1. app or dapp calls normal ENS resolution
2. ENS Universal Resolver reaches Knot's offchain resolver
3. resolver emits `OffchainLookup`
4. client calls Knot public gateway
5. gateway decodes the request
6. gateway looks up the requested profile record
7. gateway ABI-encodes the result
8. gateway signs the response payload
9. Universal Resolver verifies it through the callback path
10. client receives the resolved record

The app should keep using ENS forward resolution as usual.

## Public CCIP Gateway

The CCIP gateway should be a stable unversioned route:

- `GET /ccip/ens/{sender}/{data}.json`

Example:

- `https://api.knot.fi/ccip/ens/{sender}/{data}.json`

This route should stay unversioned because the resolver contract stores the URL template.

### Request contract

- `sender`
  - resolver contract address
  - lowercased
  - `0x`-prefixed

- `data`
  - ABI-encoded calldata
  - `0x`-prefixed

### Supported selectors

The gateway should support:

- `resolve(bytes,bytes)`
  - ENSIP-10 wildcard entrypoint
- inner `addr(bytes32)`
- inner `addr(bytes32,uint256)`
- inner `text(bytes32,string)`
- inner `contenthash(bytes32)`

### Gateway work

The gateway should:

1. validate route params
2. decode the outer `resolve(bytes,bytes)` calldata
3. decode the DNS wire-format name
4. decode the inner calldata and selector
5. resolve the profile by full `name`
6. map the requested record to a profile field
7. ABI-encode the result
8. sign the result payload with the resolver signer
9. return:

```json
{
  "data": "0x..."
}
```

### Gateway errors

The gateway should return:

- `400`
  - invalid calldata
  - invalid sender
  - unsupported selector

- `404`
  - name not found
  - requested record absent

- `500`
  - internal failure

It should also set:

- `Access-Control-Allow-Origin: *`

### Exact selector handling

The outer selector should be:

- `0x9061b923`
  - `resolve(bytes,bytes)`

The gateway should reject unsupported outer selectors with `400`.

The supported inner selectors should be:

- `0x3b3b57de`
  - `addr(bytes32)`
- `0xf1cb7e06`
  - `addr(bytes32,uint256)`
- `0x59d1d43c`
  - `text(bytes32,string)`
- `0xbc1c58d1`
  - `contenthash(bytes32)`

### Exact signing contract

The gateway should sign the encoded result using the ENS offchain resolver convention:

1. compute `result`
2. compute `expires`
3. compute the response hash from:
   - `0x1900`
   - `sender`
   - `expires`
   - `keccak256(data)`
   - `keccak256(result)`
4. sign that hash with the resolver signer key
5. ABI-encode:

```text
(bytes result, uint64 expires, bytes sig)
```

6. return:

```json
{
  "data": "0x..."
}
```

The signer key should be dedicated to the CCIP gateway.
It should not be reused for unrelated app operations.

### Robustness rules

The gateway should:

- only serve reads
- never mutate profile state
- keep signer logic isolated to the gateway service
- keep signatures short-lived, for example `5m`
- cache read results aggressively
- validate supported domain suffixes such as `*.not.fi`

## Reverse Lookup API

Reverse lookup should not rely on ENS.

The app should use a public backend route instead:

- `GET /public/profile/reverse?address=0x...`

Suggested response:

```json
{
  "address": "0xabc...",
  "name": "pizza.not.fi",
  "avatar": "https://cdn.knot.fi/avatar.jpg",
  "bio": "..."
}
```

This is how the app should bootstrap profile state on login.

The client can still cache the returned profile locally.

## Public Profile Read API

Knot should also expose a public read path by name:

- `GET /public/profile/name?name=pizza.not.fi`

This route is useful for:

- app profile reads without CCIP ceremony
- debugging
- internal tooling
- future web clients

Both public read routes should be:

- unauthenticated
- read-only
- cache-first

## Authenticated Profile Write API

Profile writes should use normal authenticated app APIs.

Suggested route surface:

- `POST /v1/profile`
  - create or update profile

Possible request shape:

```json
{
  "jsonrpc": "2.0",
  "method": "knot_profileUpdate",
  "params": {
    "name": "pizza.not.fi",
    "avatar": "https://cdn.knot.fi/avatar.jpg",
    "bio": "..."
  },
  "id": "req_123"
}
```

This route should:

- require authenticated user context
- enforce address ownership from the session
- enforce unique `name <-> address` binding
- update the authoritative store
- refresh the public read indexes
- invalidate or overwrite cached public records

The backend should own all profile mutation rules.

## Storage Model

The profile system should use:

- `D1` as authoritative profile store
- `KV` as public read index and response cache

### D1

Suggested `profiles` table fields:

- `address`
- `name`
- `avatar`
- `bio`
- `updated_at`
- `created_at`

Suggested invariants:

- `address` unique
- `name` unique
- `name` must end with `.not.fi`

This is the source of truth.

The canonical lookup keys should be:

- `name`
- `address`

### KV

Suggested public index keys:

- `profile:name:{name}`
- `profile:address:{address}`

Suggested value:

```json
{
  "address": "0xabc...",
  "name": "pizza.not.fi",
  "avatar": "https://cdn.knot.fi/avatar.jpg",
  "bio": "...",
  "updatedAt": "2026-04-04T12:00:00Z"
}
```

Suggested response cache keys:

- `ccip:response:{sender}:{data}`

The public read path should be:

- `KV` first
- `D1` fallback
- refresh KV on miss

This keeps the public surface fast without making KV the only truth.

## Record Mapping

The public gateway should map supported records from the profile model:

- `addr()`
  - `profile.address`
- `text("avatar")`
  - `profile.avatar`
- `text("description")`
  - `profile.bio`
- `contenthash()`
  - optional future field
- `addr(bytes32,uint256)`
  - optional future multichain address map

V1 only needs:

- `addr()`
- `text("avatar")`
- `text("description")`

Anything else can return `404` until supported.

## Name Policy

The profile system should keep name ownership simple:

- one address owns one active profile name
- one profile name maps to one address
- changing the name updates both indexes atomically

The backend should reject:

- duplicate names
- invalid suffixes
- mismatched authenticated address updates

## App Integration

The app should change in these ways:

- keep ENS forward resolution for `*.not.fi`
- stop using ENS reverse lookup for profile bootstrap
- stop writing profile records through ENS text-record payloads
- stop using `.eth` registration commit/reveal for Knot profile identity
- fetch reverse/profile data from Knot backend on login
- keep local cache warmup on login

The profile app model becomes:

- backend profile record is source of truth
- ENS is the public lookup layer

## Migration Direction

If Knot adopts this model, the old `.eth` profile flow should be removed from the primary product path.

That means deleting or de-emphasizing:

- ENS commit/reveal persistence
- ENS registration quoting
- ENS text-record write orchestration
- reverse-ENS-based profile discovery

What remains useful:

- forward ENS resolution abstraction
- local profile cache
- avatar upload UX

## Operational Notes

To keep the system robust:

- isolate the resolver signer from normal app write APIs
- keep the CCIP route read-only
- log unsupported selector requests
- cache successful gateway responses for short periods
- keep profile write invalidation immediate
- monitor `404` and signature-failure rates

This makes the system:

- cheaper
- simpler
- easier to reason about
- easier to evolve than the `.eth` commit/reveal profile model

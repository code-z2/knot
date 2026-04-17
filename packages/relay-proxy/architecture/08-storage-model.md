# Storage Model

Relay Proxy V1 should keep storage small, explicit, and split by responsibility.

The storage model should be:

- D1 for durable relational state and policy
- KV for short-lived or aggregate state
- Durable Objects for atomic live gas-account workflow
- separate KV namespaces for unrelated responsibilities

## Principles

- do not use one KV namespace for everything
- do not put durable policy into KV
- do not put short-lived replay and queue state into D1 unless it needs relational querying

This keeps the backend predictable and easier to operate.

## KV Namespaces

### AUTH_KV

Purpose:

- challenges
- nonces

These are short-lived auth artifacts.
They do not belong in the same KV as relay or gas tank state.

### DEFERRED_RELAY_KV

Purpose:

- deferred `UserOperation` storage keyed by `fillId`

Suggested key:

- `deferred-userop:{fillId}`

Suggested value:

- `fillId`
- `userId`
- `chainId`
- `entryPoint`
- `userOperation`
- `createdAt`
- `expiresAt`

### GAS_TANK_KV

Purpose:

- usage aggregate buckets

Suggested usage key:

- `gas-usage:{userId}:{yyyy-mm-dd}`

Suggested value:

- `totalUsdc`
- `chains`
- `updatedAt`

These are daily usage buckets with TTL.
They are not the user's policy profile and not the live gas-account store.

### PROFILE_PUBLIC_KV

Purpose:

- public profile read indexes
- CCIP response cache

Suggested profile keys:

- `profile:name:{name}`
- `profile:address:{address}`

Suggested value:

- `address`
- `name`
- `avatar`
- `bio`
- `updatedAt`

Suggested gateway cache key:

- `ccip:response:{sender}:{data}`

These keys support:

- fast public reverse lookup
- fast public name lookup
- short-lived CCIP gateway caching

They are not the authoritative profile store.

## Durable Objects

### Gas Account Durable Object

Purpose:

- live pending exposure state
- atomic per-user sponsor admission
- atomic per-user gas-account mutation

This should be one Durable Object domain per user.

## D1

D1 should hold durable state that benefits from relational querying and history.

### App/Auth durability

Current auth records already belong here:

- users
- passkeys
- app attestations
- sessions

### Profile durability

The ENS offchain profile system should store the authoritative profile record in D1.

Suggested `profiles` fields:

- `address`
- `name`
- `avatar`
- `bio`
- `created_at`
- `updated_at`

Suggested invariants:

- `address` unique
- `name` unique
- `name` must be within the supported ENS suffix, such as `.not.fi`

This is the source of truth for profile writes.

### Gas account and overdraft policy

Gas Tank V1 should store the authoritative durable gas account in D1.

Suggested fields:

- `user_id`
- `minimum_allowed_usdc`
- `overdraft_eligible`
- `overdraft_enabled`
- `overdraft_locked`
- `overdraft_outstanding_usdc`
- `outstanding_debt_usdc`
- `updated_at`

This is the authoritative durable product, policy, and debt record.

## No Relay Plan Table In V1

Relay V1 does not need a durable relay-plan table.

Reason:

- immediate and background are sent inline
- deferred payload is the only piece that must survive for later execution
- the durable gas account already covers the product-side policy state

If later versions need:

- user-facing relay history
- richer operational audit
- cross-request replay recovery

then a D1 relay-plan table can be introduced.

Do not add it in V1 unless it becomes necessary.

## Read Paths

The intended read model is:

- auth reads from D1 and AUTH_KV
- relay deferred reads from DEFERRED_RELAY_KV
- public profile reads hit PROFILE_PUBLIC_KV first and D1 on miss
- CCIP gateway reads hit PROFILE_PUBLIC_KV first and D1 on miss
- gas account reads from D1
- gas usage aggregate reads from GAS_TANK_KV
- live pending exposure reads from the Gas Account Durable Object
- final safety checks read current onchain GasTank balance

This is intentionally simple and split by job.

## Write Paths

The intended write model is:

- auth begin/finish writes to D1 and AUTH_KV
- profile writes update D1 first and then refresh PROFILE_PUBLIC_KV indexes
- relay submit writes deferred payloads to DEFERRED_RELAY_KV when needed
- relay admission and quote-based acceptance finalization mutate live exposure through the Gas Account Durable Object
- gas-account mutations persist durable debt and policy state into D1
- finalization updates the KV daily usage bucket

## Why This Split

This storage layout matches the product and operational model:

- ephemeral security data
- durable profile source of truth plus fast public indexes
- atomic live gas-account workflow
- durable user/account debt and policy state
- user-facing rolling usage aggregates

It avoids one of the most common early backend mistakes:

- using one storage primitive for unrelated jobs and then spending the next month working around it

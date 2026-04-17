# Gas Tank V1

Gas Tank V1 is the accounting and collection layer behind sponsored relay.

It is built around:

- the onchain per-user Base USDC Gas Tank
- a durable per-user gas account in D1
- a per-user Gas Account Durable Object for atomic runtime exposure
- post-execution actual-cost accounting
- periodic protocol debt collection
- overdraft policy
- durable usage history

The onchain contract remains the source of actual user funds.
The backend owns sponsor admission, debt tracking, and collection timing around those funds.

## Onchain Source Of Truth

The gas tank contract on Base remains the source of escrowed funds.

See [GAS_TANK.md](/Users/peter/Developer/knot/contracts/architecture/GAS_TANK.md).

Important properties:

- one Gas Tank per user
- Base USDC only
- real balance is onchain
- protocol cosigner can collect from the tank
- owner can withdraw immediately with cosign
- owner can withdraw permissionlessly only after the rolling quiet period

Gas Tank V1 should not introduce an onchain per-transaction reservation ledger.

## Product Model

The iOS product already exposes these concepts:

- available balance
- overdraft eligibility
- overdraft limit
- overdraft usage
- gas usage history

Backend state should preserve those exact ideas instead of inventing a second financial model.

## Runtime And Durable State

Gas Tank V1 no longer uses reservation records as the primary accounting primitive.

Instead it tracks two different classes of sponsor exposure:

- `pendingExposureUsdc`
  - sponsor risk from accepted but unresolved relay
- `outstandingDebtUsdc`
  - realized debt from completed relay that has not yet been collected

The intended state split is:

- `pendingExposureUsdc` in a per-user Durable Object
- `outstandingDebtUsdc` in the durable D1 gas account row
- current balance read from the onchain Gas Tank

This keeps the hot admission path atomic without turning D1 into a high-churn runtime store.

## Admission Rule

When deciding whether to accept a new sponsored relay, the backend should check:

- current onchain Gas Tank balance
- durable outstanding debt
- current pending exposure
- current overdraft policy

The effective sponsor headroom is:

```text
effectiveHeadroomUsdc =
  onchainBalanceUsdc
  - outstandingDebtUsdc
  - pendingExposureUsdc
  + overdraftHeadroomUsdc
```

A new sponsored relay is allowed only if:

```text
effectiveHeadroomUsdc >= quotedMaxChargeUsdc
```

Where:

- `quotedMaxChargeUsdc` comes from server-side relay quote data
- `overdraftHeadroomUsdc = 0` for users without overdraft
- `overdraftHeadroomUsdc = abs(minimumAllowedUsdc)` for users with overdraft enabled and eligible

If the user falls below the allowed floor, Relay V1 should stop accepting new sponsored relay until the position is repaired.

## Sponsor Lifecycle

### 1. Admission

On accept:

- quote the exact sponsored relay
- check effective headroom
- increment `pendingExposureUsdc`
- submit the relay operation to the bundler

### 2. Finalization

Relay Proxy charges from the server-side Gelato quote produced for the current relay request.

- if the bundler rejects before accepting the operation, release `pendingExposureUsdc`
- if the bundler accepts the operation, increment durable `outstandingDebtUsdc` by the quoted charge
- release `pendingExposureUsdc`
- increment usage history

Plan requests are billed as an aggregate plan charge. If the plan reaches the accepted execution phase, the user owes the full quoted plan charge even when individual background operations report failure. Clients are expected to simulate operations before submission; Gelato still performs its own admission checks.

Conceptually:

```text
pendingExposureUsdc -= quotedChargeUsdc
outstandingDebtUsdc += quotedChargeUsdc
```

### 3. Collection

Collection is not performed after every receipt.

Gas Tank V1 should use periodic collection plus withdrawal-time collection.

The collectible amount is:

```text
collectibleUsdc = min(onchainBalanceUsdc, outstandingDebtUsdc)
```

Once collection succeeds:

```text
outstandingDebtUsdc -= collectibleUsdc
```

Collection should be triggered by:

- fast withdrawal before cosigning
- periodic collection sweep
- optional opportunistic collection when operationally cheap

## Monthly Collection Model

The protocol should avoid immediate per-receipt collection because that doubles settlement gas burden.

Instead:

- the current server-side Gelato quote is realized into durable debt after bundler acceptance
- debt is collected on a periodic sweep
- the sweep should run before the permissionless withdrawal window, for example day `29`
- fast withdrawal should still collect debt first before returning a cosignature

The collection unit is the user, not the individual relay.

This means the queue and worker model should operate on:

- users with collectible debt

not on:

- one reservation per relay

## Overdraft

Overdraft is a policy layer, not a hidden internal hack.

Gas Tank V1 should model:

- `minimumAllowedUsdc`
- `overdraftEligible`
- `overdraftEnabled`
- `overdraftLocked`
- `overdraftOutstandingUsdc`

Backend behavior:

- if balance is sufficient at collection time, collect debt and reduce any outstanding overdraft exposure
- if balance is insufficient, leave remaining debt outstanding and enforce policy through admission checks
- if the user exceeds the allowed floor, stop accepting new sponsored relay

If the user's position is below the allowed floor:

- new relay is rejected
- overdraft should not be toggleable off until repaid

## Gas Account

Gas Tank V1 should keep one durable gas account per user in D1.

Suggested fields:

- `userId`
- `minimumAllowedUsdc`
- `overdraftEligible`
- `overdraftEnabled`
- `overdraftLocked`
- `overdraftOutstandingUsdc`
- `outstandingDebtUsdc`
- `updatedAt`

This record is the authoritative durable gas-account snapshot used by:

- relay admission
- user-facing gas views
- debt collection
- overdraft enforcement
- internal admin or support tooling

Current balance should not be cached here.
Current balance is read from the onchain Gas Tank when needed.

## Usage Aggregate

V1 does not need a relational usage history log.

It only needs:

- total gas spent over a rolling period
- per-chain gas spent over that rolling period

So usage should live in KV as daily buckets with TTL.

Suggested key:

- `gas-usage:{userId}:{yyyy-mm-dd}`

Suggested value:

- `totalUsdc`
- `chains`
- `updatedAt`

Example:

```json
{
  "totalUsdc": "1.42",
  "chains": {
    "8453": "0.91",
    "42161": "0.51"
  },
  "updatedAt": "2026-03-27T12:00:00Z"
}
```

Each finalized actual charge should update the current UTC daily bucket.

Reads for:

- `90d`
- `120d`
- `1y`

should aggregate the active daily bucket keys inside that window.

Gas usage aggregate should exclude internal debt-collection bookkeeping.

## Contract Surface

The Base Gas Tank should stay narrow.

Core functions:

- `deposit(uint256 amount)`
- `withdraw(uint256 amount, address to, uint256 deadline, bytes cosignerSig)`
- `collect(uint256 amount, address to)` or the current `debit(uint256 amount, address to)` equivalent
- `withdrawPermissionless(uint256 amount, address to)`

Core state:

- `owner`
- `cosigner`
- `withdrawNonce`
- `lastProtocolCollectionAt`
- `permissionlessWithdrawalDelay`

Rules:

- fast withdrawal is available with protocol cosign
- every protocol collection updates `lastProtocolCollectionAt`
- permissionless withdrawal is available only after:

```text
block.timestamp >= lastProtocolCollectionAt + permissionlessWithdrawalDelay
```

This gives the protocol a bounded collection window while preserving eventual user exit.

## Safety Rule

Do not infer balances or collectibility purely offchain.

For admission and collection decisions, use:

- current onchain Gas Tank balance
- current durable gas-account state
- current pending exposure from the user's Durable Object

This is safer than trying to maintain a synthetic offchain balance.

## V1 Simplicity Rule

Gas Tank V1 should stay predictable:

- onchain funds in a per-user Base Gas Tank
- one durable gas account per user in D1
- one Gas Account Durable Object per user for atomic exposure tracking
- gas usage aggregate in KV daily buckets
- actual collection performed by periodic workers and withdraw-time settlement

That is enough to be robust without carrying the operational weight of a per-reservation settlement system.

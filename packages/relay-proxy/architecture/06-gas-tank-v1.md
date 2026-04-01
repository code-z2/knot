# Gas Tank V1

Gas Tank V1 is the accounting and settlement layer behind sponsored relay.

It is built around:

- the onchain per-user Base USDC GasTank
- operational reservation state
- post-execution settlement
- overdraft policy
- durable usage history

The onchain contract remains the source of actual user funds.
The backend owns the operational pipeline around those funds.

## Onchain Source Of Truth

The gas tank contract on Base remains the source of escrowed funds.

See [GAS_TANK.md](/Users/peter/Developer/knot/contracts/architecture/GAS_TANK.md).

Important properties:

- one GasTank per user
- Base USDC only
- real balance is onchain
- protocol cosigner can `debit(amount, to)`
- owner can withdraw or forced-withdraw

Gas Tank V1 should not introduce an onchain reservation ledger.

## Product Model

The iOS product already exposes these concepts:

- available balance
- overdraft eligibility
- overdraft limit
- overdraft usage
- gas usage history

So backend state should preserve those exact ideas instead of inventing a different mental model.

## Reservation Model

Reservations are operational holds, not permanent ledger records.

They exist so the protocol can avoid sponsoring more relay work than the user's gas position can support.

Reservations should be:

- short-lived
- queue-driven
- eventually settled or released

Reservation state belongs in KV, not in the GasTank contract.

## Admission Rule

When deciding whether to accept a new sponsored relay, the backend should check:

- current onchain GasTank balance
- open reservations
- current overdraft policy

The effective available amount is:

```text
availableToReserve = onchainBalanceUsdc - openReservationAmountUsdc
```

A new relay is allowed only if:

```text
availableToReserve - estimatedReservationUsdc >= minimumAllowedUsdc
```

Where:

- `minimumAllowedUsdc = 0` for users without overdraft
- `minimumAllowedUsdc = -2 USDC` for users with overdraft eligibility

If a user goes below the overdraft floor, Relay V1 should stop accepting new sponsored transactions until the balance is repaired.

## Overdraft

Overdraft is a policy layer, not a hidden internal hack.

Gas Tank V1 should model:

- `minimumAllowedUsdc`
- `overdraftEnabled`
- `overdraftOutstandingUsdc`

Backend behavior:

- if onchain balance is sufficient at settlement time, collect the pending reservation and resolve any outstanding overdraft
- if onchain balance is insufficient, let the user's position move into overdraft up to the allowed floor
- if the user exceeds the overdraft floor, stop accepting new sponsored relay

If the user's account is below zero beyond the allowed floor:

- new relay is rejected
- overdraft should not be toggleable off until it is repaid

## Reservation Lifecycle

### 1. Quote-backed reservation amount

For `single`, `immediate`, and `background`, reservation amount should be based on backend quote data.

The backend should not reserve from:

- user-supplied fee assumptions
- raw incoming fee fields inside the `UserOperation`

Instead:

- derive the supported quote token from chain policy
- get the quote needed for sponsored execution
- create reservation from that server-side view

### 2. Reservation creation

Reservation should be created after the relevant relay work is sent and quote/task context exists.

That keeps reservation aligned with actual sponsor work rather than purely hypothetical client intent.

### 3. Settlement

After execution confirms:

- actual cost is resolved
- a pending debit record is created
- debit worker later debits the user's Base GasTank

### 4. Release or finalize

Once the debit succeeds:

- reservation is marked settled
- gas profile is updated
- usage history is written

If the reservation is never debited successfully:

- retries continue up to the policy limit
- then anomaly handling takes over

## Settlement Model

Settlement is post-execution.

That means:

- reserve optimistically for admission safety
- settle with actual values later

The debit target should be the protocol billing or treasury address on Base.
That treasury can then replenish Gelato centrally.

This keeps the onchain debit surface simple and avoids binding the GasTank contract to provider-specific funding flows.

## Gas Profile

Gas Tank V1 should keep one aggregated gas profile per user in KV.
Gas Tank V1 should keep one durable gas profile per user in D1.

Suggested fields:

- `userId`
- `minimumAllowedUsdc`
- `overdraftEligible`
- `overdraftEnabled`
- `overdraftLocked`
- `overdraftOutstandingUsdc`
- `updatedAt`

This record is the authoritative product and policy snapshot used by:

- relay admission
- user-facing gas tank views
- overdraft policy enforcement
- internal admin or support tools

Current balance should not be cached here.
Current balance is read from the onchain GasTank when the endpoint needs it.

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

Each successful debit should update the current UTC daily bucket.

Reads for:

- `90d`
- `120d`
- `1y`

should aggregate the active daily bucket keys inside that window.

This keeps usage simple and lets KV TTL prune old buckets automatically.
Gas usage aggregate should exclude overdraft resolution bookkeeping.

## Safety Rule

Do not infer balance deltas offchain.

For settlement and overdraft decisions, use:

- current onchain GasTank balance
- current reservation state

This is safer than trying to maintain a purely synthetic internal balance.

## V1 Simplicity Rule

Gas Tank V1 should stay predictable:

- onchain funds in GasTank
- reservations in a per-user Durable Object
- gas profile and overdraft policy in D1
- gas usage aggregate in KV daily buckets
- actual debits performed by queued workers

That is enough to be robust without introducing a heavy financial backend on day one.

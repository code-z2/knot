# Queues And Anomalies

Relay Proxy V1 needs queues, but only for the parts that are truly asynchronous.

The queue system should stay lean:

- deferred relay execution is queued
- periodic debt collection is queued or swept
- anomaly notification delivery is queued

Immediate and background relay are not queued in V1.

## Queue Set

V1 should have three independent queue concerns:

- deferred relay queue
- debt collection sweep
- anomaly queue

They should not be collapsed into one opaque catch-all pipe.

## Deferred Relay Queue

Purpose:

- send deferred `executeIntent` `UserOperation`s
- retry failed deferred sends
- stop retrying near TTL
- escalate anomalies when deferred work is about to expire unrecovered

The queue payload should stay small.

Suggested payload:

- `fillId`
- `userId`
- `chainId`
- `attempt`
- `expiresAt`

The actual deferred `UserOperation` should still be loaded from `DEFERRED_RELAY_KV`.

### Deferred retry rule

If deferred relay fails:

- requeue while still safely before TTL
- stop requeueing when close to expiry
- emit anomaly instead

The queue payload should not carry the whole `UserOperation`.
It should carry only the minimal routing identity.

## Debt Collection Sweep

Purpose:

- turn durable user debt into onchain Base Gas Tank collections
- batch collections where operationally useful
- retry failed collection attempts
- update the durable gas account after successful collection

The collection unit is the user, not the individual relay.

Suggested payload or work item:

- `userId`
- optional `scheduledAt`
- optional `attempt`

The collection worker should resolve the rest from D1, the user's Gas Account Durable Object, and onchain state.

### Collection worker behavior

For each indebted user:

1. read the durable gas account from D1
2. skip if `outstandingDebtUsdc == 0`
3. read the user's current onchain Gas Tank balance
4. compute:

```text
collectibleUsdc = min(onchainBalanceUsdc, outstandingDebtUsdc)
```

5. if batching is enabled, place the user into a batch collection plan
6. submit one or more Base collection transactions
7. finalize the durable debt reduction through the user's Gas Account Durable Object

If collection fails:

- increment attempts
- retry up to the configured limit
- emit anomaly after the final retry budget is exhausted

Collection should also run on the fast withdrawal path before the protocol agrees to cosign an immediate withdrawal.

## Anomaly Queue

The anomaly queue is independent.

It should not receive rich operational objects.
It should receive a plain notification payload that is already safe to fan out.

Suggested message:

- `type`
- `severity`
- `title`
- `body`
- `userId` nullable
- `fillId` nullable
- `collectionUserId` nullable
- `createdAt`

The anomaly worker's job is delivery, not reconstruction.

It should push messages through configured channels, such as:

- internal ops inbox
- push notification
- email
- Discord or Slack

## Cron Responsibilities

V1 should use cron to keep queues moving and to recover stuck work.

### Relay cron

Relay cron should:

- find deferred work that still needs submission
- push it to the deferred relay queue
- skip items too close to TTL
- emit anomaly for near-expiry failures instead of requeueing forever

### Collection cron

Collection cron should:

- find users with `outstandingDebtUsdc > 0`
- push them to the collection worker or iterate them directly
- avoid pushing already exhausted retries
- emit anomaly once the retry budget is exhausted

## Retry Policy

Retry budgets should be small and explicit.

Suggested V1 rule:

- retry deferred relay up to a bounded count while TTL remains healthy
- retry debt collection up to `3` times
- after the final failed retry, emit anomaly and stop automated retries

This keeps queue behavior predictable and makes the anomaly channel meaningful.

## Durable Objects

Durable Objects should own live gas-account runtime state in V1.

Use one Gas Account Durable Object per user.

That Durable Object should own hot atomic state such as:

- `pendingExposureUsdc`
- atomic per-user gas-account mutations
- finalization of durable debt updates after quote-based bundler acceptance and collection

This keeps hot financial mutation out of weak concurrent KV writes while leaving the rest of the system simple:

- Deferred userops in KV
- usage aggregate in KV
- durable gas account and policy in D1
- queues for asynchronous execution, collection, and anomaly delivery

## Design Rule

The queue system should not become a second application layer.

Its job is:

- asynchronous dispatch
- bounded retry
- anomaly escalation

It should not own protocol truth or long-lived financial state.

# Queues And Anomalies

Relay Proxy V1 needs queues, but only for the parts that are truly asynchronous.

The queue system should stay lean:

- deferred relay execution is queued
- reservation debit settlement is queued
- anomaly notification delivery is queued

Immediate and background relay are not queued in V1.

## Queue Set

V1 should have three independent queue concerns:

- deferred relay queue
- reservation settlement queue
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

## Reservation Settlement Queue

Purpose:

- turn pending reservations into onchain GasTank debits
- retry failed debit attempts
- update gas profile and usage aggregate

Suggested payload:

- `reservationId`
- `userId`
- `attempt`

The settlement worker should resolve the rest from KV and onchain state.

### Settlement worker behavior

For each pending reservation:

1. read the reservation from the user's reservation Durable Object
2. read the user's current onchain GasTank balance
3. decide whether to:
   - debit normally
   - spend into overdraft
   - reject because the user is beyond overdraft floor
4. submit `gasTank.debit(...)`
5. update reservation status
6. update D1 gas profile if overdraft state changed
7. update the KV daily usage bucket

If debit fails:

- increment attempts
- retry up to the configured limit
- emit anomaly after the final retry budget is exhausted

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
- `reservationId` nullable
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

### Reservation cron

Reservation cron should:

- find reservations in pending settlement state
- push them to the settlement queue
- avoid pushing already exhausted retries
- emit anomaly once the retry budget is exhausted

## Retry Policy

Retry budgets should be small and explicit.

Suggested V1 rule:

- retry deferred relay up to a bounded count while TTL remains healthy
- retry reservation debit up to `3` times
- after the final failed retry, emit anomaly and stop automated retries

This keeps queue behavior predictable and makes the anomaly channel meaningful.

## Durable Objects

Durable Objects should own live reservation state in V1.

Use one reservation Durable Object per user.

That Durable Object should own:

- open reservations
- reservation status transitions
- retry counters
- atomic per-user reservation updates

This keeps live reservation mutation out of weak concurrent KV writes while leaving the rest of the system simple:

- Deferred userops in KV
- usage aggregate in KV
- gas profile and policy in D1
- queues for asynchronous execution and settlement

## Design Rule

The queue system should not become a second application layer.

Its job is:

- asynchronous dispatch
- bounded retry
- anomaly escalation

It should not own protocol truth or long-lived financial state.

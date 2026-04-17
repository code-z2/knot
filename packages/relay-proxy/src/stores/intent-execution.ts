/**
 * KV-backed store for deferred intent-execution records.
 *
 * When a relay `plan` request includes a `deferred` operation (an
 * ERC-4337 UserOp that should be submitted later, typically after a
 * cross-chain fill is confirmed), the relay handler stores the
 * serialized record here. The CRON-triggered sweep
 * ({@link sweepIntentExecutions}) re-queues stale records, and the
 * queue consumer ({@link consumeIntentExecutionBatch}) submits them
 * to the bundler.
 *
 * Records are keyed by `intent-exec:{fillId}` and auto-expire via
 * KV TTL after {@link INTENT_EXECUTION_TTL_SECONDS}, providing a
 * hard upper bound on retry duration.
 *
 * @module
 */
import { INTENT_EXECUTION_KEY_PREFIX, INTENT_EXECUTION_TTL_SECONDS } from '@/constants';
import type { CloudflareBindings, IntentExecutionRecord } from '@/types';
import { parseJsonRecord } from '@/utils';

export function createIntentExecutionStore(env: Pick<CloudflareBindings, 'RELAY_KV'>) {
    const withKey = <ReturnType, RestArgs extends unknown[] = []>(
        fn: (key: string, ...args: RestArgs) => ReturnType,
        fillId: string,
        ...args: RestArgs
    ) => {
        const key = `${INTENT_EXECUTION_KEY_PREFIX}${fillId}`;
        return fn(key, ...args);
    };

    return {
        async delete(fillId: string) {
            await withKey(env.RELAY_KV.delete, fillId);
        },

        async get(fillId: string): Promise<IntentExecutionRecord | null> {
            const raw = await withKey<Promise<string | null>>(env.RELAY_KV.get, fillId);
            return parseJsonRecord<IntentExecutionRecord>(raw);
        },

        list(cursor?: string) {
            return env.RELAY_KV.list({
                cursor,
                prefix: INTENT_EXECUTION_KEY_PREFIX,
            });
        },

        async put(record: IntentExecutionRecord, ttlSeconds = INTENT_EXECUTION_TTL_SECONDS): Promise<void> {
            await withKey(env.RELAY_KV.put, record.fillId, JSON.stringify(record), {
                expirationTtl: ttlSeconds,
            });
        },
    };
}

/** Stamp a record with an incremented attempt count and queue timestamp. */
export function withQueuedAttempt(record: IntentExecutionRecord, now: string): IntentExecutionRecord {
    return {
        ...record,
        attempts: record.attempts + 1,
        lastQueuedAt: now,
    };
}

/** Stamp a record with the latest anomaly notification timestamp. */
export function withAnomalyTimestamp(record: IntentExecutionRecord, now: string): IntentExecutionRecord {
    return {
        ...record,
        lastAnomalyAt: now,
    };
}

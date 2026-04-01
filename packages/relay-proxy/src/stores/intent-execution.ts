import { INTENT_EXECUTION_KEY_PREFIX, INTENT_EXECUTION_TTL_SECONDS } from '@/constants';
import type { CloudflareBindings, IntentExecutionRecord } from '@/types';

export function createIntentExecutionStore(env: Pick<CloudflareBindings, 'RELAY_KV'>) {
    return {
        async delete(fillId: string) {
            await withKey(env.RELAY_KV.delete, fillId);
        },

        async get(fillId: string): Promise<IntentExecutionRecord | null> {
            const raw = await withKey<Promise<string | null>>(env.RELAY_KV.get, fillId);

            if (!raw) {
                return null;
            }

            return JSON.parse(raw) as IntentExecutionRecord;
        },

        list(cursor?: string) {
            return env.RELAY_KV.list({
                cursor,
                prefix: INTENT_EXECUTION_KEY_PREFIX,
            });
        },

        async put(
            record: IntentExecutionRecord,
            ttlSeconds = INTENT_EXECUTION_TTL_SECONDS,
        ): Promise<void> {
            await withKey(env.RELAY_KV.put, record.fillId, JSON.stringify(record), {
                expirationTtl: ttlSeconds,
            });
        },
    };
}

export function withKey<ReturnType, RestArgs extends unknown[] = []>(
    fn: (key: string, ...args: RestArgs) => ReturnType,
    fillId: string,
    ...args: RestArgs
) {
    const key = `${INTENT_EXECUTION_KEY_PREFIX}${fillId}`;
    return fn(key, ...args);
}

export function withQueuedAttempt(
    record: IntentExecutionRecord,
    now: string,
): IntentExecutionRecord {
    return {
        ...record,
        attempts: record.attempts + 1,
        lastQueuedAt: now,
    };
}

export function withAnomalyTimestamp(
    record: IntentExecutionRecord,
    now: string,
): IntentExecutionRecord {
    return {
        ...record,
        lastAnomalyAt: now,
    };
}

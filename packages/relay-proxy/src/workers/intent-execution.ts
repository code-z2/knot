import {
    INTENT_EXECUTION_ANOMALY_RETRY_AFTER_MS,
    INTENT_EXECUTION_KEY_PREFIX,
    INTENT_EXECUTION_MAX_ATTEMPTS,
    INTENT_EXECUTION_RETRY_AFTER_MS,
    INTENT_EXECUTION_TTL_SECONDS,
} from '@/constants';
import { createBundlerClient } from '@/services/bundler';
import {
    createIntentExecutionStore,
    withAnomalyTimestamp,
    withQueuedAttempt,
} from '@/stores/intent-execution';
import type {
    CloudflareBindings,
    IntentExecutionQueueMessage,
    IntentExecutionRecord,
    RelayDeferredResult,
    RelayPlanParams,
} from '@/types';
import { createIntentExecutionAnomaly, getChainConfig, isExpired, isNearExpiry } from '@/utils';

export async function consumeIntentExecutionBatch(
    batch: MessageBatch<IntentExecutionQueueMessage>,
    env: Pick<CloudflareBindings, 'RELAY_KV' | 'BUNDLER_API_KEY' | 'JSON_RPC_API_KEY'>,
    client: typeof createBundlerClient = createBundlerClient,
    now = Date.now(),
): Promise<void> {
    const store = createIntentExecutionStore(env);

    for (const message of batch.messages) {
        try {
            const record = await store.get(message.body);
            const chain = getChainConfig(record?.chainId);

            // if chain is not supported, how did it make to the queue?
            if (!record || !chain || isExpired(record, now)) {
                if (record) {
                    await store.delete(record.fillId);
                }
                message.ack();
                continue;
            }

            const bundlerClient = client(env, chain, {});

            await bundlerClient.sendUserOperation(record.userOperation, record.entryPoint);
            await store.delete(record.fillId);
            message.ack();
        } catch {
            message.retry();
        }
    }
}

export async function sweepIntentExecutions(
    env: Pick<CloudflareBindings, 'ANOMALY_QUEUE' | 'RELAY_KV' | 'RELAY_QUEUE'>,
    now = Date.now(),
): Promise<void> {
    const store = createIntentExecutionStore(env);
    let cursor: string | undefined;

    do {
        const listResult = await store.list(cursor);

        for (const key of listResult.keys) {
            const fillId = key.name.slice(INTENT_EXECUTION_KEY_PREFIX.length);
            const record = await store.get(fillId);

            if (!record || isExpired(record, now)) {
                if (record) {
                    await store.delete(record.fillId);
                }
                continue;
            }

            const msSinceLastQueued = record.lastQueuedAt
                ? now - Date.parse(record.lastQueuedAt)
                : Infinity;

            const msSinceLastAnomaly = record.lastAnomalyAt
                ? now - Date.parse(record.lastAnomalyAt)
                : Infinity;

            if (msSinceLastQueued < INTENT_EXECUTION_RETRY_AFTER_MS) continue;

            const anomalyKind = isNearExpiry(record, now)
                ? 'near_expiry'
                : record.attempts >= INTENT_EXECUTION_MAX_ATTEMPTS
                  ? 'retry_exhausted'
                  : null;

            if (anomalyKind) {
                if (msSinceLastAnomaly >= INTENT_EXECUTION_ANOMALY_RETRY_AFTER_MS) {
                    const timestamp = new Date(now).toISOString();
                    await env.ANOMALY_QUEUE.send(
                        createIntentExecutionAnomaly(record, now, anomalyKind),
                    );
                    await store.put(withAnomalyTimestamp(record, timestamp));
                }
                continue;
            }

            await env.RELAY_QUEUE.send(record.fillId);
            await store.put(withQueuedAttempt(record, new Date(now).toISOString()));
        }

        cursor = listResult.list_complete ? undefined : listResult.cursor;
    } while (cursor);
}

export async function storeIntentExecution(
    env: Pick<CloudflareBindings, 'RELAY_QUEUE' | 'RELAY_KV' | 'ANOMALY_QUEUE'>,
    params: RelayPlanParams,
    now = Date.now(),
): Promise<RelayDeferredResult> {
    const store = createIntentExecutionStore(env);

    const record: IntentExecutionRecord = {
        attempts: 0,
        chainId: params.chainId,
        createdAt: new Date(now).toISOString(),
        entryPoint: params.request[1],
        expiresAt: new Date(now + INTENT_EXECUTION_TTL_SECONDS * 1000).toISOString(),
        fillId: params.fillId,
        userOperation: params.request[0].deferred,
    };

    await store.put(record);

    let queued = false;
    try {
        await env.RELAY_QUEUE.send(record.fillId);
        queued = true;
    } catch {
        await env.ANOMALY_QUEUE.send(createIntentExecutionAnomaly(record, now, 'not_queued'));
    }

    return { fillId: record.fillId, queued };
}

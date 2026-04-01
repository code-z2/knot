import {
    INTENT_EXECUTION_ANOMALY_RETRY_AFTER_MS,
    INTENT_EXECUTION_KEY_PREFIX,
    INTENT_EXECUTION_MAX_ATTEMPTS,
    INTENT_EXECUTION_RETRY_AFTER_MS,
} from '@/constants';
import { createBundlerClient } from '@/services/bundler';
import {
    createIntentExecutionStore,
    withAnomalyTimestamp,
    withQueuedAttempt,
} from '@/stores/intent-execution';
import type { CloudflareBindings, IntentExecutionQueueMessage } from '@/types';
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

            const bundlerClient = client({
                chain,
                bundlerApiKey: env.BUNDLER_API_KEY,
                jsonRpcApiKey: env.JSON_RPC_API_KEY,
            });

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

            if (isNearExpiry(record, now) || record.attempts >= INTENT_EXECUTION_MAX_ATTEMPTS) {
                if (msSinceLastAnomaly >= INTENT_EXECUTION_ANOMALY_RETRY_AFTER_MS) {
                    await env.ANOMALY_QUEUE.send(createIntentExecutionAnomaly(record, now));
                    await store.put(withAnomalyTimestamp(record, new Date(now).toISOString()));
                }
                continue;
            }

            await env.RELAY_QUEUE.send(record.fillId);
            await store.put(withQueuedAttempt(record, new Date(now).toISOString()));
        }

        cursor = listResult.list_complete ? undefined : listResult.cursor;
    } while (cursor);
}

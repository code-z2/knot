/**
 * Async worker for deferred intent-execution — the retry loop that
 * ensures cross-chain `deferred` UserOperations eventually land on-chain.
 *
 * ## Lifecycle
 *
 * 1. **Store** ({@link storeIntentExecution}): The relay handler stores the
 *    deferred UserOp in KV and immediately enqueues its `fillId` to
 *    `RELAY_QUEUE`. If the enqueue fails, an anomaly is raised so
 *    operators know to investigate.
 *
 * 2. **Consume** ({@link consumeIntentExecutionBatch}): The queue consumer
 *    reads the KV record by `fillId`, submits the UserOp to the
 *    bundler, and deletes the record on success. Expired or orphaned
 *    records are silently cleaned up.
 *
 * 3. **Sweep** ({@link sweepIntentExecutions}): A CRON trigger paginates
 *    all `intent-exec:*` keys in KV. For each non-expired record that
 *    hasn’t been re-queued recently, it logs anomalies (TTL warning,
 *    retry exhaustion) and re-enqueues the `fillId` for another attempt.
 *
 * @module
 */
import {
    INTENT_EXECUTION_KEY_PREFIX,
    INTENT_EXECUTION_MAX_ATTEMPTS,
    INTENT_EXECUTION_RETRY_AFTER_MS,
    INTENT_EXECUTION_TTL_SECONDS,
} from '@/constants';
import { createBundlerClient } from '@/services/bundler';
import { createIntentExecutionStore, withQueuedAttempt } from '@/stores/intent-execution';
import type {
    CloudflareBindings,
    IntentExecutionQueueMessage,
    IntentExecutionRecord,
    RelayDeferredResult,
    RelayPlanParams,
} from '@/types';
import { getAnomalyLogger, getChainConfig, isExpired, isSupportedChainId, toRelayOperations } from '@/utils';
import { RpcUserOperation } from 'viem';

/**
 * Queue consumer — processes a batch of `fillId` messages, submitting
 * each deferred UserOp to the bundler. Failed messages are retried by
 * CF Queues' built-in retry mechanism.
 */
export async function consumeIntentExecutionBatch(
    batch: MessageBatch<IntentExecutionQueueMessage>,
    env: CloudflareBindings,
    client: typeof createBundlerClient = createBundlerClient,
    now = Date.now(),
): Promise<void> {
    const store = createIntentExecutionStore(env);

    for (const message of batch.messages) {
        try {
            const record = await store.get(message.body);

            if (!record || isExpired(record, now) || !isSupportedChainId(record.chainId)) {
                if (record) {
                    await store.delete(record.fillId);
                }
                message.ack();
                continue;
            }

            const chain = getChainConfig(record.chainId);
            const bundlerClient = await client(env, chain, {});

            await bundlerClient.sendUserOperation(record.userOperation, record.entryPoint);
            await store.delete(record.fillId);
            message.ack();
        } catch (error) {
            console.error('Failed to consume intent execution batch', error);
            message.retry();
        }
    }
}

/**
 * CRON sweep — paginates all intent-execution KV keys, re-queuing
 * records that are overdue for a retry attempt. Raises anomalies
 * for records nearing TTL or exceeding the retry budget.
 *
 * Records are skipped if they were queued more recently than
 * `INTENT_EXECUTION_RETRY_AFTER_MS` to prevent queue flooding.
 */
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

            const msSinceLastQueued = record.lastQueuedAt ? now - Date.parse(record.lastQueuedAt) : Infinity;

            if (msSinceLastQueued < INTENT_EXECUTION_RETRY_AFTER_MS) continue;

            const logAnomaly = getAnomalyLogger(env, 'intent_execution', now);

            if (record.attempts >= INTENT_EXECUTION_MAX_ATTEMPTS) {
                const updatedRecord = logAnomaly(record);
                if (updatedRecord) {
                    await store.put(updatedRecord);
                }
                continue;
            }

            const updatedRecord = logAnomaly(record);
            const recordToQueue = updatedRecord ?? record;
            if (updatedRecord) {
                await store.put(updatedRecord);
            }

            await env.RELAY_QUEUE.send(record.fillId);
            await store.put(withQueuedAttempt(recordToQueue, new Date(now).toISOString()));
        }

        cursor = listResult.list_complete ? undefined : listResult.cursor;
    } while (cursor);
}

/**
 * Store and enqueue a deferred UserOp from a relay plan.
 *
 * Called during the relay handler’s `plan` branch. The record is
 * written to KV first (guaranteed persistence), then enqueued.
 * If the enqueue fails, the sweep will pick it up on the next
 * CRON cycle.
 */
export async function storeIntentExecution(
    env: Pick<CloudflareBindings, 'RELAY_QUEUE' | 'RELAY_KV' | 'ANOMALY_QUEUE'>,
    params: RelayPlanParams,
    now = Date.now(),
): Promise<RelayDeferredResult> {
    const store = createIntentExecutionStore(env);

    const { chainId, userOp } = toRelayOperations(params.request[0].filter((op) => op.strategy === 'deferred')).first;

    const record: IntentExecutionRecord = {
        attempts: 0,
        chainId,
        createdAt: new Date(now).toISOString(),
        entryPoint: params.request[1],
        expiresAt: new Date(now + INTENT_EXECUTION_TTL_SECONDS * 1000).toISOString(),
        fillId: params.fillId,
        userOperation: userOp,
    };

    await store.put(record);

    let queued = false;
    try {
        await env.RELAY_QUEUE.send(record.fillId);
        queued = true;
    } catch {
        const logAnomaly = getAnomalyLogger(env, '*', now);
        logAnomaly({ record, type: 'anomaly_intent_execution_not_queued' });
    }

    return { fillId: record.fillId, queued };
}

export async function deleteIntentExecution(
    env: Pick<CloudflareBindings, 'RELAY_KV' | 'ANOMALY_QUEUE'>,
    fillId: string,
) {
    const store = createIntentExecutionStore(env);
    await store.delete(fillId);
}

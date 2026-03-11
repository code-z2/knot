import { encodeFunctionData, type Hex } from 'viem';

import {
    DEFERRED_DISPATCHED_TTL_SECONDS,
    TRACKER_DECREMENT_BASE_DELAY_MS,
    TRACKER_DECREMENT_MAX_ATTEMPTS,
} from '../../shared/constants';
import { MULTICALL3_ADDRESS, MULTICALL3_TRY_AGGREGATE_ABI } from '../../shared/abis/multicall3';
import { sendRelayTransaction } from '../services/gelato.service';
import { getWebhookTracker } from './tracker.do';

import type { Env, SupportMode } from '../../shared/types';
import type { AlertQueueMessage, QueueMessageExecuteIntent, RelayQueueMessage } from '../types';

/**
 * Main RELAY_BATCH_QUEUE consumer.
 * Groups `execute_intent` messages by (chainId, supportMode) and dispatches efficiently.
 */
export async function consumeRelayBatch(
    batch: MessageBatch<RelayQueueMessage>,
    env: Env,
): Promise<void> {
    const executeIntents: QueueMessageExecuteIntent[] = [];

    for (const message of batch.messages) {
        if (message.body.type === 'execute_intent') {
            executeIntents.push(message.body);
        }
    }

    try {
        await processExecuteIntents(executeIntents, env);
    } catch (error) {
        console.error('[queue.worker] Batch processing error:', error);
    }

    // Ack all regardless — failures are logged, not retried (avoids duplicate dispatches).
    // The Sweeper Cron handles recovery for dropped intents.
    for (const message of batch.messages) {
        message.ack();
    }
}

// ---------------------------------------------------------------------------
// Execute Intents (Multicall3 Non-Atomic Batching)
// ---------------------------------------------------------------------------

/**
 * Groups intents by (chainId + supportMode) and dispatches them.
 * Single intents bypass Multicall3 formatting to save gas overhead.
 */
async function processExecuteIntents(
    intents: QueueMessageExecuteIntent[],
    env: Env,
): Promise<void> {
    if (intents.length === 0) return;

    const groups = groupBy(intents, (i) => `${i.chainId}:${i.supportMode}`);

    for (const [key, group] of groups) {
        const [chainIdStr, supportMode] = key.split(':') as [string, SupportMode];
        const chainId = Number(chainIdStr);

        try {
            if (group.length === 1) {
                const intent = group[0];
                const submission = await sendRelayTransaction(
                    'relayer_sendTransaction',
                    { chainId, supportMode, request: intent.request },
                    supportMode,
                    env,
                );

                await postDispatch([intent], submission.id, supportMode, env);
            } else {
                const gelatoId = await dispatchMulticallBatch(chainId, supportMode, group, env);
                await postDispatch(group, gelatoId, supportMode, env);
            }
        } catch (error) {
            console.error(`[queue.worker] Failed to dispatch intents for ${key}:`, error);
        }
    }
}

/** Encodes multiple intents into a Multicall3 `tryAggregate` payload and dispatches. */
async function dispatchMulticallBatch(
    chainId: number,
    supportMode: SupportMode,
    intents: QueueMessageExecuteIntent[],
    env: Env,
): Promise<string> {
    const calls = intents.map((intent) => ({
        target: intent.request.to,
        callData: intent.request.data,
    }));

    const multicallData = encodeFunctionData({
        abi: MULTICALL3_TRY_AGGREGATE_ABI,
        functionName: 'tryAggregate',
        args: [false, calls],
    });

    const submission = await sendRelayTransaction(
        'relayer_sendTransaction',
        {
            chainId,
            supportMode,
            request: {
                from: intents[0].request.from,
                to: MULTICALL3_ADDRESS,
                data: multicallData as Hex,
            },
        },
        supportMode,
        env,
    );

    return submission.id;
}

/**
 * Shared post-dispatch logic: marks all KV entries with the gelatoId and
 * decrements the webhook tracker for each unique accumulator.
 */
async function postDispatch(
    intents: QueueMessageExecuteIntent[],
    gelatoId: string,
    supportMode: SupportMode,
    env: Env,
): Promise<void> {
    await Promise.allSettled(
        intents.map((intent) =>
            markDeferredAsDispatched(intent.fillId, supportMode, gelatoId, env),
        ),
    );

    const uniqueAccumulators = [...new Set(intents.map((i) => i.accumulatorAddress))];
    await Promise.allSettled(uniqueAccumulators.map((addr) => decrementWebhookTracker(addr, env)));
}

/** Updates the deferred KV entry with the gelatoId for client-side status polling. */
async function markDeferredAsDispatched(
    fillId: string,
    supportMode: SupportMode,
    gelatoId: string,
    env: Env,
): Promise<void> {
    const key = `deferred-relay:${supportMode}:${fillId}`;
    const raw = await env.DEFERRED_RELAY_KV.get(key);
    if (!raw) return;

    try {
        const payload = JSON.parse(raw) as Record<string, unknown>;
        payload.gelatoId = gelatoId;
        await env.DEFERRED_RELAY_KV.put(key, JSON.stringify(payload), {
            expirationTtl: DEFERRED_DISPATCHED_TTL_SECONDS,
        });
    } catch {
        console.error(`[queue.worker] Failed to update KV for fillId ${fillId}`);
    }
}

/**
 * Decrements the webhook tracker with exponential backoff.
 * Sends an alert if all retries are exhausted (prevents silent zombie subscriptions).
 */
async function decrementWebhookTracker(accumulatorAddress: string, env: Env): Promise<void> {
    const tracker = getWebhookTracker(accumulatorAddress, env);
    let lastError: unknown;

    for (let attempt = 1; attempt <= TRACKER_DECREMENT_MAX_ATTEMPTS; attempt++) {
        try {
            await tracker.fetch(new Request('https://do/decrement', { method: 'POST' }));
            return;
        } catch (error) {
            lastError = error;
            console.warn(
                `[queue.worker] DO decrement attempt ${attempt}/${TRACKER_DECREMENT_MAX_ATTEMPTS} failed for ${accumulatorAddress}:`,
                error,
            );

            if (attempt < TRACKER_DECREMENT_MAX_ATTEMPTS) {
                await sleep(TRACKER_DECREMENT_BASE_DELAY_MS * 2 ** (attempt - 1));
            }
        }
    }

    console.error(`[queue.worker] DO decrement exhausted retries for ${accumulatorAddress}`);

    try {
        await env.ALERTS_QUEUE.send({
            type: 'anomaly_tracker_decrement_failed',
            accumulatorAddress,
            attempts: TRACKER_DECREMENT_MAX_ATTEMPTS,
            error: lastError instanceof Error ? lastError.message : String(lastError),
        } satisfies AlertQueueMessage);
    } catch {
        console.error(
            `[queue.worker] Failed to send decrement-failure alert for ${accumulatorAddress}`,
        );
    }
}

function sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function groupBy<T>(items: T[], keyFn: (item: T) => string): Map<string, T[]> {
    const map = new Map<string, T[]>();
    for (const item of items) {
        const key = keyFn(item);
        const group = map.get(key);
        if (group) {
            group.push(item);
        } else {
            map.set(key, [item]);
        }
    }
    return map;
}

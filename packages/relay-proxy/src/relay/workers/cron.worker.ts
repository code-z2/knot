import {
    DEFERRED_TX_TTL_SECONDS,
    DEFERRED_TTL_WARNING_DAYS,
    STUCK_THRESHOLD_MS,
} from '../../shared/constants';
import { FILL_READY_EVENT } from '../../shared/abis/accumulator';
import { createChainClient } from '../../shared/chains';

import type { Env } from '../../shared/types';
import type { AlertQueueMessage, DeferredRelayKVPayload, RelayQueueMessage } from '../types';

const TTL_WARNING_MS = DEFERRED_TTL_WARNING_DAYS * 24 * 60 * 60 * 1000;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * Sweeper Cron: scans DEFERRED_RELAY_KV for intents older than the stuck threshold
 * that haven't been dispatched. Verifies FillReady on-chain before re-queuing
 * to avoid false positives from slow bridging.
 */
export async function sweepDeferredIntents(env: Env): Promise<void> {
    const now = Date.now();
    let recoveredCount = 0;
    let cursor: string | undefined;

    do {
        const listResult = await env.DEFERRED_RELAY_KV.list({
            prefix: 'deferred-relay:',
            cursor,
        });

        for (const key of listResult.keys) {
            try {
                const raw = await env.DEFERRED_RELAY_KV.get(key.name);
                if (!raw) continue;

                const payload = JSON.parse(raw) as DeferredRelayKVPayload;
                const accumulatorAddress = payload.request.to.toLowerCase();

                const createdAt = new Date(payload.createdAt).getTime();
                const ageMs = now - createdAt;

                // Alert if undispatched intent is approaching KV TTL expiration
                if (!payload.gelatoId && ageMs >= TTL_WARNING_MS) {
                    await env.ALERTS_QUEUE.send({
                        type: 'anomaly_deferred_ttl_expiring',
                        accumulatorAddress,
                        fillId: payload.fillId,
                        supportMode: payload.supportMode,
                        chainId: payload.chainId,
                        ageDays: Math.round(ageMs / MS_PER_DAY),
                        ttlDays: Math.round(DEFERRED_TX_TTL_SECONDS / 86_400),
                    } satisfies AlertQueueMessage);
                }

                if (payload.gelatoId) continue;

                if (ageMs < STUCK_THRESHOLD_MS) continue;

                const fillReady = await verifyFillReadyOnChain(
                    payload.chainId,
                    accumulatorAddress,
                    payload.fillId,
                    env,
                );

                if (!fillReady) continue;

                console.warn(
                    `[sweeper.cron] Recovering stuck intent: ${payload.fillId} (age: ${Math.round(ageMs / 1000)}s)`,
                );

                await env.RELAY_BATCH_QUEUE.send({
                    type: 'execute_intent',
                    accumulatorAddress,
                    fillId: payload.fillId,
                    supportMode: payload.supportMode,
                    chainId: payload.chainId,
                    request: payload.request,
                } satisfies RelayQueueMessage);

                await env.ALERTS_QUEUE.send({
                    type: 'anomaly_sweeper_recovery',
                    accumulatorAddress,
                    fillId: payload.fillId,
                    supportMode: payload.supportMode,
                    chainId: payload.chainId,
                    recoveredAt: new Date().toISOString(),
                } satisfies AlertQueueMessage);

                recoveredCount++;
            } catch (error) {
                console.error(`[sweeper.cron] Error processing key ${key.name}:`, error);
            }
        }

        cursor = listResult.list_complete ? undefined : listResult.cursor;
    } while (cursor);

    if (recoveredCount > 0) {
        console.warn(`[sweeper.cron] Recovered ${recoveredCount} stuck intent(s).`);
    }
}

/**
 * Checks on-chain whether the Accumulator emitted a FillReady event
 * for the specific fillId. Filters by the indexed fillId topic to avoid
 * false positives from other intents on the same accumulator.
 * Returns false on error to avoid incorrectly re-dispatching intents.
 */
async function verifyFillReadyOnChain(
    chainId: number,
    accumulatorAddress: string,
    fillId: string,
    env: Env,
): Promise<boolean> {
    try {
        const client = createChainClient(chainId, env.ALCHEMY_NODE_API_KEY);

        const logs = await client.getLogs({
            address: accumulatorAddress as `0x${string}`,
            event: FILL_READY_EVENT,
            args: { fillId: fillId as `0x${string}` },
            fromBlock: 'earliest',
            toBlock: 'latest',
        });

        return logs.length > 0;
    } catch (error) {
        console.error(`[sweeper.cron] On-chain check failed for ${accumulatorAddress}:`, error);
        return false;
    }
}

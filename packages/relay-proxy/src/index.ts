/**
 * Cloudflare Worker entry point — the three lifecycle hooks that define
 * relay-proxy's runtime surface.
 *
 * - **fetch**: All HTTP traffic routes through the Hono app ({@link app}).
 * - **queue**: Processes CF Queue bindings in a shared consumer.
 *   `anomaly-queue` messages are Discord webhook notifications;
 *   `faucet-queue` messages trigger fire-and-forget testnet funding;
 *   `intent-execution-queue` messages are deferred ERC-4337 operations
 *   that couldn't be submitted synchronously during the relay flow.
 *   The exhaustive switch guarantees a compile error if a new queue is
 *   added without a matching handler.
 * - **scheduled**: A CRON trigger that sweeps stale intent-execution
 *   records in KV, re-queuing operations that haven't been retried
 *   recently and raising anomalies for those nearing TTL or retry limits.
 *
 * @module
 */
import type { AppBatchQueue, CloudflareBindings } from '@/types';
import { consumeAnomalyBatch, consumeFaucetBatch, consumeIntentExecutionBatch, sweepIntentExecutions } from '@/workers';
import { FaucetDurableObject } from './durable-objects/faucet';
import { GasAccountDurableObject } from './durable-objects/gas';
import app from './app';

export { FaucetDurableObject };
export { GasAccountDurableObject };

export default {
    async fetch(request: Request, env: CloudflareBindings, ctx: ExecutionContext) {
        return app.fetch(request, env, ctx);
    },

    async queue(batch: AppBatchQueue, env: CloudflareBindings): Promise<void> {
        switch (batch.queue) {
            case 'anomaly-queue':
                await consumeAnomalyBatch(batch, env);
                break;
            case 'faucet-queue':
                await consumeFaucetBatch(batch, env);
                break;
            case 'intent-execution-queue':
                await consumeIntentExecutionBatch(batch, env);
                break;
            default: {
                const _exhaustive: never = batch;
                console.error(`[queue] Unknown queue: ${(batch as MessageBatch<unknown>).queue}`);
            }
        }
    },

    async scheduled(_controller: ScheduledController, env: CloudflareBindings): Promise<void> {
        await sweepIntentExecutions(env);
    },
};

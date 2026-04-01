import type { AppBatchQueue, CloudflareBindings } from '@/types';
import { consumeAnomalyBatch, consumeIntentExecutionBatch, sweepIntentExecutions } from '@/workers';
import app from './app';

export default {
    async fetch(request: Request, env: CloudflareBindings, ctx: ExecutionContext) {
        return app.fetch(request, env, ctx);
    },

    async queue(batch: AppBatchQueue, env: CloudflareBindings): Promise<void> {
        switch (batch.queue) {
            case 'anomaly-queue':
                await consumeAnomalyBatch(batch, env);
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

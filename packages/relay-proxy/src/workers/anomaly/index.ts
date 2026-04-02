import type { AnomalyBindings, AnomalyQueueMessage } from '@/types';
import { sendDiscordAnomaly } from './discord';

export async function consumeAnomalyBatch(
    batch: MessageBatch<AnomalyQueueMessage>,
    env: AnomalyBindings,
): Promise<void> {
    for (const message of batch.messages) {
        try {
            await dispatchAnomaly(message.body, env);
            message.ack();
        } catch {
            message.retry();
        }
    }
}

async function dispatchAnomaly(anomaly: AnomalyQueueMessage, env: AnomalyBindings): Promise<void> {
    const dispatchers: Array<Promise<void>> = [];

    dispatchers.push(sendDiscordAnomaly(anomaly, env));

    const results = await Promise.allSettled(dispatchers);

    if (results.some((result) => result.status === 'rejected')) {
        throw new Error('anomaly_dispatch_failed');
    }
}

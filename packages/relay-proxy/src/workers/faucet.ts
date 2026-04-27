import type { CloudflareBindings, FaucetFundDOResult, FaucetQueueMessage } from '@/types';
import { doRequestHandler, getAnomalyLogger } from '@/utils';

export async function consumeFaucetBatch(
    batch: MessageBatch<FaucetQueueMessage>,
    env: Pick<CloudflareBindings, 'ANOMALY_QUEUE' | 'FAUCET_DO'>,
): Promise<void> {
    const makeDORequest = doRequestHandler(env, 'FAUCET_DO');
    const logAnomaly = getAnomalyLogger(env, 'faucet');

    for (const message of batch.messages) {
        try {
            const result = await makeDORequest<FaucetFundDOResult>(message.body, '/fund', {
                method: 'POST',
            });

            if (result.status === 'partial') {
                logAnomaly(message.body);
            }

            message.ack();
        } catch (error) {
            console.error('[faucet-worker] failed to process message', error);
            message.retry();
        }
    }
}

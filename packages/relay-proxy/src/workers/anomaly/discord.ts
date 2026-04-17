import type { AnomalyBindings, AnomalyQueueMessage } from '@/types';
import { buildOutboundAnomalyMessage } from '@/utils';

export async function sendDiscordAnomaly(anomaly: AnomalyQueueMessage, env: AnomalyBindings): Promise<void> {
    const webhookUrl = env.DISCORD_WEBHOOK_URL;
    if (!webhookUrl) {
        return;
    }

    const response = await fetch(webhookUrl, {
        body: JSON.stringify({
            content: buildOutboundAnomalyMessage(anomaly),
        }),
        headers: {
            'Content-Type': 'application/json',
        },
        method: 'POST',
    });

    if (!response.ok) {
        throw new Error(`discord_webhook_failed:${response.status}`);
    }
}

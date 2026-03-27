import type { Env } from '../../shared/types';
import type { AlertQueueMessage } from '../types';

/** Consumes the ALERTS_QUEUE and fans out notifications to configured external channels. */
export async function consumeAlertsBatch(
    batch: MessageBatch<AlertQueueMessage>,
    env: Env,
): Promise<void> {
    for (const message of batch.messages) {
        try {
            await dispatchAlert(message.body, env);
            message.ack();
        } catch (error) {
            console.error('[alerts] Failed to dispatch alert:', error);
            message.retry();
        }
    }
}

async function dispatchAlert(alert: AlertQueueMessage, env: Env): Promise<void> {
    const dispatchers: Array<() => Promise<void>> = [];

    if (env.DISCORD_ANOMALY_WEBHOOK_URL) {
        dispatchers.push(() => sendDiscordAlert(alert, env.DISCORD_ANOMALY_WEBHOOK_URL as string));
    }

    await Promise.allSettled(dispatchers.map((fn) => fn()));
}

async function sendDiscordAlert(alert: AlertQueueMessage, webhookUrl: string): Promise<void> {
    const response = await fetch(webhookUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ content: buildAlertMessage(alert) }),
    });

    if (!response.ok) {
        const text = await response.text();
        throw new Error(`Discord webhook failed (${response.status}): ${text}`);
    }
}

function buildAlertMessage(alert: AlertQueueMessage): string {
    switch (alert.type) {
        case 'anomaly_sweeper_recovery':
            return [
                '\u{1f6a8} **Sweeper Recovery** \u{1f6a8}',
                '',
                `**Accumulator:** \`${alert.accumulatorAddress}\``,
                `**Chain:** ${alert.chainId} · **Mode:** ${alert.supportMode}`,
                `**Recovered At:** ${alert.recoveredAt}`,
                '',
                'Alchemy webhook missed `FillReady`. Sweeper recovered the intent.',
            ].join('\n');

        case 'anomaly_tracker_decrement_failed':
            return [
                '\u{26a0}\u{fe0f} **Tracker Decrement Failed** \u{26a0}\u{fe0f}',
                '',
                `**Accumulator:** \`${alert.accumulatorAddress}\``,
                `**Attempts:** ${alert.attempts}`,
                `**Error:** ${alert.error}`,
                '',
                'Webhook tracker refcount may be stale — Alchemy subscription will not be removed automatically. Manual cleanup required.',
            ].join('\n');

        case 'anomaly_deferred_ttl_expiring':
            return [
                '\u{23f3} **Deferred Intent Approaching TTL** \u{23f3}',
                '',
                `**Accumulator:** \`${alert.accumulatorAddress}\``,
                `**Fill ID:** \`${alert.fillId}\``,
                `**Chain:** ${alert.chainId} · **Mode:** ${alert.supportMode}`,
                `**Age:** ${alert.ageDays} days / ${alert.ttlDays} day TTL`,
                '',
                'This intent has not been dispatched and will expire from KV soon. Investigate why the bridge has not settled.',
            ].join('\n');
    }
}

import type { AnomalyQueueMessage } from '@/types';

export function buildAnomalyMessage(anomaly: AnomalyQueueMessage): string {
    const metadata = buildAnomalyMetadata(anomaly);

    return [
        `${severityPrefix(anomaly.severity)} **${anomaly.title}**`,
        '',
        anomaly.body,
        '',
        ...metadata,
    ].join('\n');
}

export function severityPrefix(severity: AnomalyQueueMessage['severity']) {
    switch (severity) {
        case 'critical':
            return '🚨';
        case 'warning':
            return '⚠️';
        case 'info':
            return 'ℹ️';
    }
}

export function buildAnomalyMetadata(anomaly: AnomalyQueueMessage): string[] {
    switch (anomaly.type) {
        case 'anomaly_intent_execution_ttl_expiring':
        case 'anomaly_intent_execution_retry_exhausted':
            return [
                `**User:** \`${anomaly.userId}\``,
                `**Fill ID:** \`${anomaly.fillId}\``,
                `**Created At:** ${anomaly.createdAt}`,
                `**Type:** \`${anomaly.type}\``,
            ];
        case 'anomaly_reservation_retry_exhausted':
            return [
                `**User:** \`${anomaly.userId}\``,
                `**Reservation ID:** \`${anomaly.reservationId}\``,
                `**Created At:** ${anomaly.createdAt}`,
                `**Type:** \`${anomaly.type}\``,
            ];
        case 'anomaly_faucet_funding_failed':
            return [
                `**User:** \`${anomaly.userId}\``,
                `**Created At:** ${anomaly.createdAt}`,
                `**Type:** \`${anomaly.type}\``,
            ];
        default:
            throw new Error(`Unknown anomaly type: ${anomaly.type}`);
    }
}

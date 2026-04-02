import { INTENT_EXECUTION_TTL_WARNING_MS } from '@/constants';
import { AnomalyQueueMessage, IntentExecutionRecord } from '@/types';

export function createIntentExecutionAnomaly(
    record: IntentExecutionRecord,
    now: number,
    reason: 'near_expiry' | 'retry_exhausted' | 'not_queued',
): AnomalyQueueMessage {
    let variant: {
        body: string;
        title: string;
        type:
            | 'anomaly_intent_execution_ttl_expiring'
            | 'anomaly_intent_execution_retry_exhausted'
            | 'anomaly_intent_execution_not_queued';
    };
    switch (reason) {
        case 'near_expiry':
            variant = {
                body: 'Intent execution is nearing TTL and will stop retrying automatically.',
                title: 'Intent execution nearing TTL',
                type: 'anomaly_intent_execution_ttl_expiring' as const,
            };
            break;
        case 'retry_exhausted':
            variant = {
                body: 'Intent execution exhausted its retry budget and needs operator attention.',
                title: 'Intent execution retry budget exhausted',
                type: 'anomaly_intent_execution_retry_exhausted' as const,
            };
            break;
        case 'not_queued':
            variant = {
                body: 'Intent execution was not queued and needs operator attention.',
                title: 'Intent execution not queued',
                type: 'anomaly_intent_execution_not_queued' as const,
            };
            break;
    }

    return {
        ...variant,
        createdAt: new Date(now).toISOString(),
        fillId: record.fillId,
        severity: 'warning',
        userId: record.userOperation.sender,
    };
}

export function isExpired(record: IntentExecutionRecord, now: number) {
    return Date.parse(record.expiresAt) <= now;
}

export function isNearExpiry(record: IntentExecutionRecord, now: number) {
    return Date.parse(record.expiresAt) - now <= INTENT_EXECUTION_TTL_WARNING_MS;
}

import { INTENT_EXECUTION_TTL_WARNING_MS } from '@/constants';
import { AnomalyQueueMessage, IntentExecutionRecord } from '@/types';

export function createIntentExecutionAnomaly(
    record: IntentExecutionRecord,
    now: number,
): AnomalyQueueMessage {
    const nearExpiry = isNearExpiry(record, now);

    const variant = nearExpiry
        ? {
              body: 'Intent execution is nearing TTL and will stop retrying automatically.',
              title: 'Intent execution nearing TTL',
              type: 'anomaly_intent_execution_ttl_expiring' as const,
          }
        : {
              body: 'Intent execution exhausted its retry budget and needs operator attention.',
              title: 'Intent execution retry budget exhausted',
              type: 'anomaly_intent_execution_retry_exhausted' as const,
          };

    return {
        ...variant,
        createdAt: new Date(now).toISOString(),
        fillId: record.fillId,
        severity: 'warning',
        userId: record.userId,
    };
}

export function isExpired(record: IntentExecutionRecord, now: number) {
    return Date.parse(record.expiresAt) <= now;
}

export function isNearExpiry(record: IntentExecutionRecord, now: number) {
    return Date.parse(record.expiresAt) - now <= INTENT_EXECUTION_TTL_WARNING_MS;
}

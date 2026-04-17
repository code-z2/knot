/**
 * Anomaly subsystem — builds structured alert messages for operational
 * incidents and routes them to the Discord webhook via CF Queues.
 *
 * Anomalies are raised when the system detects conditions that require
 * operator attention but don’t warrant blocking the user’s request:
 *
 * - Intent executions nearing their TTL or exhausting retry budgets
 * - Failed faucet funding for testnet users
 * - Gas-accounting failures after a relay has already been accepted
 *
 * The {@link getAnomalyLogger} factory provides overloaded return types
 * so callers get the narrowest possible function signature for their
 * use case (intent-execution records vs. faucet vs. generic).
 *
 * @module
 */
import {
    INTENT_EXECUTION_ANOMALY_RETRY_AFTER_MS,
    INTENT_EXECUTION_MAX_ATTEMPTS,
    INTENT_EXECUTION_TTL_WARNING_MS,
} from '@/constants';
import { withAnomalyTimestamp } from '@/stores/intent-execution';
import { AnomalyQueueMessage, AnomalyType, CloudflareBindings, IntentExecutionRecord } from '@/types';

/**
 * Build a CF Queue message body for an operational anomaly.
 *
 * This is the inbound side — called at detection time. The message is
 * enqueued and later consumed by the anomaly batch worker, which
 * formats it via {@link buildOutboundAnomalyMessage} for Discord.
 *
 * Uses an exhaustive switch with a `never` default to ensure every
 * {@link AnomalyType} has a matching case at compile time.
 */
export function buildInboundAnomalyMessage(
    info:
        | {
              record: IntentExecutionRecord;
              type: Exclude<AnomalyType, 'anomaly_faucet_funding_failed' | 'anomaly_relay_gas_accounting_failed'>;
          }
        | {
              type: 'anomaly_faucet_funding_failed';
              userId: string;
          }
        | {
              chargeUsdc: string;
              failures: readonly unknown[];
              type: 'anomaly_relay_gas_accounting_failed';
              userId: string;
          },
    timestamp: string,
): AnomalyQueueMessage {
    switch (info.type) {
        case 'anomaly_intent_execution_ttl_expiring':
            return {
                body: 'Intent execution is nearing TTL and will stop retrying automatically.',
                createdAt: timestamp,
                fillId: info.record.fillId,
                severity: 'warning',
                title: 'Intent execution nearing TTL',
                type: info.type,
                userId: info.record.userOperation.sender,
            };
        case 'anomaly_intent_execution_retry_exhausted':
            return {
                body: 'Intent execution exhausted its retry budget and needs operator attention.',
                createdAt: timestamp,
                fillId: info.record.fillId,
                severity: 'warning',
                title: 'Intent execution retry budget exhausted',
                type: info.type,
                userId: info.record.userOperation.sender,
            };
        case 'anomaly_intent_execution_not_queued':
            return {
                body: 'Intent execution was not queued and needs operator attention.',
                createdAt: timestamp,
                fillId: info.record.fillId,
                severity: 'critical',
                title: 'Intent execution not queued',
                type: info.type,
                userId: info.record.userOperation.sender,
            };
        case 'anomaly_faucet_funding_failed':
            return {
                body: 'Faucet was unable to process a funding request.',
                createdAt: timestamp,
                severity: 'critical',
                title: 'Faucet funding failed',
                type: info.type,
                userId: info.userId,
            };
        case 'anomaly_relay_gas_accounting_failed':
            return {
                body: 'Relay gas accounting failed after relay acceptance. Operator attention is required because the relay cannot be reverted.',
                chargeUsdc: info.chargeUsdc,
                createdAt: timestamp,
                failures: info.failures,
                severity: 'critical',
                title: 'Relay gas accounting failed',
                type: info.type,
                userId: info.userId,
            };
        default:
            const _exhaustive: never = info;
            return _exhaustive;
    }
}

export function buildOutboundAnomalyMessage(anomaly: AnomalyQueueMessage): string {
    const metadata = buildAnomalyMetadata(anomaly);

    return [`${severityPrefix(anomaly.severity)} **${anomaly.title}**`, '', anomaly.body, '', ...metadata].join('\n');
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
        case 'anomaly_intent_execution_not_queued':
            return [
                `**User:** \`${anomaly.userId}\``,
                `**Fill ID:** \`${anomaly.fillId}\``,
                `**Created At:** ${anomaly.createdAt}`,
                `**Type:** \`${anomaly.type}\``,
            ];
        case 'anomaly_faucet_funding_failed':
            return [
                `**User:** \`${anomaly.userId}\``,
                `**Created At:** ${anomaly.createdAt}`,
                `**Type:** \`${anomaly.type}\``,
            ];
        case 'anomaly_relay_gas_accounting_failed':
            return [
                `**User:** \`${anomaly.userId}\``,
                `**Charge USDC:** \`${anomaly.chargeUsdc}\``,
                `**Failures:** \`${anomaly.failures.join(' | ')}\``,
                `**Created At:** ${anomaly.createdAt}`,
                `**Type:** \`${anomaly.type}\``,
            ];
    }

    const _exhaustive: never = anomaly;
    throw new Error(`Unknown anomaly type: ${String(_exhaustive)}`);
}

export function isExpired(record: IntentExecutionRecord, now: number) {
    return Date.parse(record.expiresAt) <= now;
}

export function isNearExpiry(record: IntentExecutionRecord, now: number) {
    return Date.parse(record.expiresAt) - now <= INTENT_EXECUTION_TTL_WARNING_MS;
}

/**
 * Factory that returns a typed anomaly logger for a specific domain.
 *
 * The overload signatures ensure that:
 * - `'intent_execution'` callers receive a logger that accepts an
 *   `IntentExecutionRecord` and returns an updated record (or null
 *   if no anomaly was detected).
 * - `'faucet'` callers receive a fire-and-forget `(userId) => void`.
 * - `'*'` callers receive a generic logger for ad-hoc anomalies.
 *
 * The intent-execution variant includes a debounce check: anomalies
 * are only re-sent if at least `INTENT_EXECUTION_ANOMALY_RETRY_AFTER_MS`
 * has elapsed since the last notification, preventing Discord spam
 * for records that are retried frequently.
 */
export function getAnomalyLogger(
    env: Pick<CloudflareBindings, 'ANOMALY_QUEUE'>,
    type: 'intent_execution',
    now?: number,
): (record: IntentExecutionRecord) => IntentExecutionRecord | null;

export function getAnomalyLogger(
    env: Pick<CloudflareBindings, 'ANOMALY_QUEUE'>,
    type: 'faucet',
    now?: number,
): (userId: string) => void;

export function getAnomalyLogger(
    env: Pick<CloudflareBindings, 'ANOMALY_QUEUE'>,
    type: '*',
    now?: number,
): (info: Parameters<typeof buildInboundAnomalyMessage>[0]) => void;

export function getAnomalyLogger(
    env: Pick<CloudflareBindings, 'ANOMALY_QUEUE'>,
    type: 'intent_execution' | 'faucet' | '*',
    now = Date.now(),
) {
    const timestamp = new Date(now).toISOString();
    switch (type) {
        case 'intent_execution':
            return (record: IntentExecutionRecord) => {
                let type: AnomalyType | null = null;
                if (isNearExpiry(record, now)) {
                    type = 'anomaly_intent_execution_ttl_expiring';
                }
                if (record.attempts >= INTENT_EXECUTION_MAX_ATTEMPTS) {
                    type = 'anomaly_intent_execution_retry_exhausted';
                }

                if (!type) {
                    return null;
                }
                const msSinceLastAnomaly = record.lastAnomalyAt ? now - Date.parse(record.lastAnomalyAt) : Infinity;

                if (msSinceLastAnomaly >= INTENT_EXECUTION_ANOMALY_RETRY_AFTER_MS) {
                    env.ANOMALY_QUEUE.send(buildInboundAnomalyMessage({ record, type }, timestamp));
                    return withAnomalyTimestamp(record, timestamp);
                }
            };
        case 'faucet':
            return (userId: string) => {
                env.ANOMALY_QUEUE.send(
                    buildInboundAnomalyMessage({ type: 'anomaly_faucet_funding_failed', userId }, timestamp),
                );
            };
        default:
            return (info: Parameters<typeof buildInboundAnomalyMessage>[0]) => {
                env.ANOMALY_QUEUE.send(buildInboundAnomalyMessage(info, timestamp));
            };
    }
}

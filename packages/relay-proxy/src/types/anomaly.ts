import type { CloudflareBindings, IntentExecutionRecord } from '@/types';

export type AnomalyBindings = Pick<CloudflareBindings, 'DISCORD_WEBHOOK_URL'>;

export type AnomalySeverity = 'critical' | 'info' | 'warning';

type BaseAnomalyMessage = {
    body: string;
    createdAt: string;
    severity: AnomalySeverity;
    title: string;
};

export type IntentExecutionTtlExpiringAnomaly = BaseAnomalyMessage & {
    fillId: string;
    type: 'anomaly_intent_execution_ttl_expiring';
    userId: string;
};

export type IntentExecutionRetryExhaustedAnomaly = BaseAnomalyMessage & {
    fillId: string;
    type: 'anomaly_intent_execution_retry_exhausted';
    userId: string;
};

export type FaucetFundingFailedAnomaly = BaseAnomalyMessage & {
    type: 'anomaly_faucet_funding_failed';
    userId: string;
};

export type RelayGasAccountingFailedAnomaly = BaseAnomalyMessage & {
    chargeUsdc: string;
    failures: readonly unknown[];
    type: 'anomaly_relay_gas_accounting_failed';
    userId: string;
};

export type IntentExecutionNotQueuedAnomaly = BaseAnomalyMessage & {
    fillId: string;
    type: 'anomaly_intent_execution_not_queued';
    userId: string;
};

export type AnomalyQueueMessage =
    | FaucetFundingFailedAnomaly
    | IntentExecutionNotQueuedAnomaly
    | IntentExecutionRetryExhaustedAnomaly
    | IntentExecutionTtlExpiringAnomaly
    | RelayGasAccountingFailedAnomaly;

export type AnomalyType = AnomalyQueueMessage['type'];

/**
 * Relay-specific types. Shared types (Env, SupportMode, PaymentOptionModel)
 * live in shared/types.ts.
 */
import type { Address, Hex } from 'viem';

import type { SupportMode } from '../shared/types';

// ---------------------------------------------------------------------------
// EIP-7702 / Relay Transaction Types
// ---------------------------------------------------------------------------

export interface RelayAuthorizationModel {
    address: Address;
    chainId: number;
    nonce: number;
    r: Hex;
    s: Hex;
    yParity: 0 | 1;
}

export interface RelayTransactionRequestModel {
    from: Address;
    to: Address;
    data: Hex;
    value?: Hex;
    authorizationList?: readonly RelayAuthorizationModel[];
}

export interface RelayTxEnvelopeModel {
    chainId: number;
    supportMode?: SupportMode;
    request: RelayTransactionRequestModel;
}

export type RelayMethod = 'relayer_sendTransaction' | 'relayer_sendTransactionSync';

// ---------------------------------------------------------------------------
// Request / Response Models
// ---------------------------------------------------------------------------

export interface SubmitRelayRequestModel {
    account: string;
    supportMode: SupportMode;
    immediateTxs: RelayTxEnvelopeModel[];
    backgroundTxs: RelayTxEnvelopeModel[];
    deferredTxs: RelayTxEnvelopeModel[];
    paymentOptions?: import('../shared/types').PaymentOptionModel[];
}

export interface RelaySubmissionModel {
    id: string;
    transactionHash?: string;
}

export interface RelayStatusModel {
    id: string;
    rawStatus: string;
    state: string;
    transactionHash?: string;
    blockNumber?: string;
    failureReason?: string;
}

export interface TankStateModel {
    balanceWei: bigint;
    initialized: boolean;
}

// ---------------------------------------------------------------------------
// Webhook Models
// ---------------------------------------------------------------------------

export type WebhookFillReadyStatus = 'dispatched' | 'not_found' | 'already_dispatched' | 'ignored';

export interface WebhookFillReadyResponse {
    ok: boolean;
    status: WebhookFillReadyStatus;
}

/** Alchemy Custom Webhook payload — mirrors our GraphQL query shape. */
export interface AlchemyWebhookPayload {
    webhookId: string;
    id: string;
    createdAt: string;
    type: string;
    event: {
        data: {
            block: {
                number: number;
                timestamp: number;
                logs: AlchemyFillReadyLog[];
            };
        };
        sequenceNumber: string;
    };
}

export interface AlchemyFillReadyLog {
    topics: string[];
    account: { address: string };
    transaction: {
        hash: string;
        status: number;
        from: { address: string };
        to: { address: string };
        value: string;
        gasUsed: number;
        effectiveGasPrice: string;
    };
}

// ---------------------------------------------------------------------------
// Queue Message & KV Payload Types
// ---------------------------------------------------------------------------

export interface QueueMessageExecuteIntent {
    type: 'execute_intent';
    accumulatorAddress: string;
    fillId: string;
    supportMode: SupportMode;
    chainId: number;
    request: RelayTransactionRequestModel;
}

export type RelayQueueMessage = QueueMessageExecuteIntent;

export type AlertQueueMessage =
    | AlertSweeperRecovery
    | AlertTrackerDecrementFailed
    | AlertDeferredTtlExpiring;

export interface AlertSweeperRecovery {
    type: 'anomaly_sweeper_recovery';
    accumulatorAddress: string;
    fillId: string;
    supportMode: SupportMode;
    chainId: number;
    recoveredAt: string;
}

export interface AlertTrackerDecrementFailed {
    type: 'anomaly_tracker_decrement_failed';
    accumulatorAddress: string;
    attempts: number;
    error: string;
}

export interface AlertDeferredTtlExpiring {
    type: 'anomaly_deferred_ttl_expiring';
    accumulatorAddress: string;
    fillId: string;
    supportMode: SupportMode;
    chainId: number;
    ageDays: number;
    ttlDays: number;
}

export interface DeferredRelayKVPayload {
    fillId: string;
    account: string;
    supportMode: SupportMode;
    chainId: number;
    request: RelayTransactionRequestModel;
    createdAt: string;
    gelatoId?: string;
}

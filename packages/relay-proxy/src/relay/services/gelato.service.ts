import {
    createGelatoEvmRelayerClient,
    StatusCode,
    type GelatoEvmRelayerClient,
    type SendTransactionParameters,
    type Status,
} from '@gelatocloud/gasless';
import { zeroAddress } from 'viem';

import { BadRequestError } from '../../shared/errors';
import { estimateRelayRequestGas } from '../gas-estimator';

import type { Env, SupportMode } from '../../shared/types';
import type {
    DeferredRelayKVPayload,
    RelayMethod,
    RelayStatusModel,
    RelaySubmissionModel,
    RelayTxEnvelopeModel,
} from '../types';

/** Quotes the total native-token fee across multiple relay envelopes via Gelato. */
export async function quoteTotalWei(
    txs: readonly RelayTxEnvelopeModel[],
    defaultSupportMode: SupportMode,
    env: Env,
): Promise<bigint> {
    let total = 0n;

    for (const tx of txs) {
        const supportMode = tx.supportMode ?? defaultSupportMode;
        const client = getClientForSupportMode(supportMode, env);
        const gas = await estimateRelayRequestGas(tx.chainId, tx.request, env);

        const quote = await client.getFeeQuote({
            chainId: tx.chainId,
            gas,
            token: zeroAddress,
        });
        total += quote.fee;
    }

    return total;
}

/** Dispatches a transaction envelope to the Gelato Relayer network. */
export async function sendRelayTransaction(
    method: RelayMethod,
    tx: RelayTxEnvelopeModel,
    defaultSupportMode: SupportMode,
    env: Env,
): Promise<RelaySubmissionModel> {
    const supportMode = tx.supportMode ?? defaultSupportMode;
    const client = getClientForSupportMode(supportMode, env);
    const payload = buildSendTransactionParameters(tx);
    const id = await client.sendTransaction(payload);

    if (method === 'relayer_sendTransactionSync') {
        const receipt = await client.waitForReceipt(
            { id },
            { usePolling: true, throwOnReverted: false },
        );
        return { id, transactionHash: receipt.transactionHash };
    }

    return { id };
}

/**
 * Unified status lookup for both standard Gelato task IDs and deferred fillIds.
 * Deffered IDs have the format `deferred-{fillId}`.
 */
export async function getRelayStatus(
    id: string,
    supportMode: SupportMode,
    env: Env,
): Promise<RelayStatusModel> {
    const relayID = id.trim();
    if (!relayID) throw new BadRequestError('Missing relay task id.');

    if (relayID.startsWith('deferred-')) {
        return getDeferredRelayStatus(relayID.split('-')[1], supportMode, env);
    }

    const client = getClientForSupportMode(supportMode, env);
    return toRelayStatusModel(await client.getStatus({ id: relayID }));
}

// ---------------------------------------------------------------------------
// Deferred Relay Status
// ---------------------------------------------------------------------------

async function getDeferredRelayStatus(
    fillId: string,
    supportMode: SupportMode,
    env: Env,
): Promise<RelayStatusModel> {
    const key = `deferred-relay:${supportMode}:${fillId}`;
    const raw = await env.DEFERRED_RELAY_KV.get(key);
    if (!raw) {
        return { id: fillId, rawStatus: 'not_found', state: 'unknown' };
    }

    const payload = JSON.parse(raw) as DeferredRelayKVPayload;
    if (payload.gelatoId) {
        const client = getClientForSupportMode(supportMode, env);
        return toRelayStatusModel(await client.getStatus({ id: payload.gelatoId }), fillId);
    }

    return { id: fillId, rawStatus: 'waiting_for_bridge', state: 'pending' };
}

// ---------------------------------------------------------------------------
// Internal Gelato Helpers
// ---------------------------------------------------------------------------

function buildSendTransactionParameters(tx: RelayTxEnvelopeModel): SendTransactionParameters {
    const parameters: SendTransactionParameters = {
        chainId: tx.chainId,
        to: tx.request.to,
        data: tx.request.data,
    };

    if (tx.request.authorizationList?.length) {
        parameters.authorizationList = [...tx.request.authorizationList];
    }

    if (tx.request.value && BigInt(tx.request.value) > 0n) {
        throw new BadRequestError(
            `Unsupported request.value for chain ${tx.chainId}; include value in execute call payload instead.`,
        );
    }

    return parameters;
}

function toRelayStatusModel(status: Status, idOverride?: string): RelayStatusModel {
    return {
        id: idOverride ?? status.id,
        rawStatus: String(status.status),
        state: StatusCode[status.status],
        transactionHash: 'hash' in status ? status.hash : undefined,
        blockNumber: extractBlockNumberHex(status),
        failureReason: 'message' in status ? status.message : undefined,
    };
}

function extractBlockNumberHex(status: Status): string | undefined {
    if (!('receipt' in status) || !status.receipt || !('blockNumber' in status.receipt)) {
        return undefined;
    }
    const blockNumber = status.receipt.blockNumber as bigint | number;
    return `0x${blockNumber.toString(16)}`;
}

function getClientForSupportMode(mode: SupportMode, env: Env): GelatoEvmRelayerClient {
    const isTestnet = mode === 'testnet';
    const apiKey = isTestnet ? env.GELATO_TESTNET_API_KEY : env.GELATO_MAINNET_API_KEY;

    if (!apiKey) {
        throw new BadRequestError(`Missing Gelato API key for mode ${mode}.`);
    }

    return createGelatoEvmRelayerClient({ apiKey, testnet: isTestnet });
}

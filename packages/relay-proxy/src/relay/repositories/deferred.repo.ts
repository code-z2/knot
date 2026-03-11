import { DEFERRED_TX_TTL_SECONDS } from '../../shared/constants';
import { deriveFillId } from '../utils/fillId';
import { getWebhookTracker } from '../workers/tracker.do';

import type { Env, SupportMode } from '../../shared/types';
import type { DeferredRelayKVPayload, RelayTxEnvelopeModel } from '../types';

/**
 * Stores a deferred transaction in DEFERRED_RELAY_KV and registers the
 * accumulator with the Webhook Tracker DO to listen for FillReady events.
 */
export async function storeDeferredTransaction(
    account: string,
    supportMode: SupportMode,
    tx: RelayTxEnvelopeModel,
    env: Env,
): Promise<string> {
    const accumulatorAddress = tx.request.to.toLowerCase();
    const fillId = deriveFillId(tx.request.data, tx.request.from);
    const key = `deferred-relay:${supportMode}:${fillId}`;

    const payload = {
        account,
        supportMode,
        chainId: tx.chainId,
        fillId,
        request: tx.request,
        createdAt: new Date().toISOString(),
    } satisfies DeferredRelayKVPayload;

    await env.DEFERRED_RELAY_KV.put(key, JSON.stringify(payload), {
        expirationTtl: DEFERRED_TX_TTL_SECONDS,
    });

    const tracker = getWebhookTracker(accumulatorAddress, env);
    await tracker.fetch(
        new Request('https://do/increment', {
            method: 'POST',
            body: JSON.stringify({ accumulatorAddress }),
        }),
    );

    return `deferred-${fillId}`;
}

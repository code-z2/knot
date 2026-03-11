import { AuthError, BadRequestError } from '../../shared/errors';
import { hmacHex, timingSafeEqual } from '../../shared/auth';
import { jsonResponse } from '../../shared/http';
import { normalizeAddress } from '../../shared/validation';
import type { Env, SupportMode } from '../../shared/types';

import type {
    AlchemyWebhookPayload,
    DeferredRelayKVPayload,
    RelayQueueMessage,
    WebhookFillReadyResponse,
    WebhookFillReadyStatus,
} from '../types';

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

/**
 * Handles Alchemy Custom Webhook payloads for FillReady events.
 * Verifies HMAC signature, resolves FillReady logs, and enqueues matching deferred intents.
 */
export async function handleWebhookFillReady(request: Request, env: Env): Promise<Response> {
    const supportMode = parseSupportMode(request.url);
    const rawBody = await request.text();
    const webhook = JSON.parse(rawBody) as AlchemyWebhookPayload;

    await verifyAlchemySignature(request, rawBody, webhook.webhookId, env);

    const logs = webhook.event.data.block.logs;
    if (logs.length === 0) {
        return jsonResponse({ ok: true, status: 'ignored' } satisfies WebhookFillReadyResponse);
    }

    // Deduplicate by fillId — same fill can appear in multiple logs.
    const unique = new Map<string, { fillId: string; accumulatorAddress: string }>();

    for (const log of logs) {
        const fillId = log.topics[1]?.toLowerCase();
        if (!fillId || !/^0x[0-9a-f]{64}$/.test(fillId)) continue;

        unique.set(fillId, {
            fillId,
            accumulatorAddress: normalizeAddress(log.account.address),
        });
    }

    if (unique.size === 0) {
        return jsonResponse({ ok: true, status: 'ignored' } satisfies WebhookFillReadyResponse);
    }

    let status: WebhookFillReadyStatus = 'not_found';

    for (const match of unique.values()) {
        const key = `deferred-relay:${supportMode}:${match.fillId}`;
        const raw = await env.DEFERRED_RELAY_KV.get(key);
        if (!raw) continue;

        const payload = JSON.parse(raw) as DeferredRelayKVPayload;

        if (payload.gelatoId) {
            status = 'already_dispatched';
            continue;
        }

        await env.RELAY_BATCH_QUEUE.send({
            type: 'execute_intent',
            accumulatorAddress: match.accumulatorAddress,
            fillId: payload.fillId,
            supportMode: payload.supportMode,
            chainId: payload.chainId,
            request: payload.request,
        } satisfies RelayQueueMessage);

        status = 'dispatched';
    }

    return jsonResponse({ ok: true, status } satisfies WebhookFillReadyResponse);
}

// ---------------------------------------------------------------------------
// Alchemy HMAC-SHA256 Signature Verification
// ---------------------------------------------------------------------------

async function verifyAlchemySignature(
    request: Request,
    rawBody: string,
    webhookId: string,
    env: Env,
): Promise<void> {
    const signature = request.headers.get('X-Alchemy-Signature');
    if (!signature) throw new AuthError('Missing X-Alchemy-Signature header.');

    const signingKey = resolveWebhookSigningKey(webhookId, env);
    const expected = await hmacHex(signingKey, rawBody);

    if (!timingSafeEqual(signature, expected)) {
        throw new AuthError('Invalid webhook signature.');
    }
}

// ---------------------------------------------------------------------------
// Route Parsing
// ---------------------------------------------------------------------------

/** Extracts supportMode from the last segment of `/v1/webhook/fill-ready/{testnet|mainnet}`. */
function parseSupportMode(requestURL: string): SupportMode {
    const scope = new URL(requestURL).pathname.split('/').pop()?.trim().toLowerCase();

    switch (scope) {
        case 'testnet':
            return 'LIMITED_TESTNET';
        case 'mainnet':
            return 'LIMITED_MAINNET';
        default:
            throw new BadRequestError('Invalid webhook scope.');
    }
}

function resolveWebhookSigningKey(webhookId: string, env: Env): string {
    const rawMap = env.ALCHEMY_WEBHOOK_SIGNING_KEYS?.trim() ?? '';
    if (rawMap) {
        let parsed: Record<string, string>;
        try {
            parsed = JSON.parse(rawMap) as Record<string, string>;
        } catch {
            throw new AuthError('Invalid ALCHEMY_WEBHOOK_SIGNING_KEYS JSON.');
        }

        const key = (parsed[webhookId] ?? '').trim();
        if (key) return key;
    }

    throw new AuthError(`Missing signing key for webhook id ${webhookId}.`);
}

import { AuthError, BadRequestError, PaymentRequiredError } from './shared/errors';
import { authorizeRequest } from './shared/auth';
import {
    corsResponse,
    isRouteAllowedForHostname,
    jsonResponse,
    normalizeHostname,
} from './shared/http';
import { formatNativeToken } from './shared/validation';

import { handleFaucetFund } from './faucet/handler';
export { FaucetTracker } from './faucet/tracker.do';

import {
    consumeAlertsBatch,
    consumeRelayBatch,
    handleCredit,
    handleRelayStatus,
    handleSubmitRelay,
    handleWebhookFillReady,
    sweepDeferredIntents,
} from './relay';
export { AccumulatorWebhookTracker } from './relay/workers/tracker.do';

import { handleSingletonVersion } from './singleton/handler';
import { handleDirectImageUpload } from './upload/handler';

import type { Env } from './shared/types';
import type { AlertQueueMessage, RelayQueueMessage } from './relay/types';

export default {
    async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
        try {
            const url = new URL(request.url);
            const path = url.pathname;
            const hostname = normalizeHostname(url.hostname);

            if (!isRouteAllowedForHostname(hostname, request.method, path)) {
                return jsonResponse({ ok: false, error: 'not_found' }, 404);
            }

            if (request.method === 'OPTIONS') {
                return corsResponse(new Response(null, { status: 204 }));
            }

            if (request.method === 'GET' && path === '/health') {
                return jsonResponse({ ok: true, service: 'relay-proxy' });
            }

            if (request.method === 'POST' && path === '/v1/relay/submit') {
                const rawBody = await request.text();
                await authorizeRequest(request, env, rawBody);
                return await handleSubmitRelay(rawBody, env);
            }

            if (request.method === 'GET' && path === '/v1/relay/status') {
                await authorizeRequest(request, env, '');
                return await handleRelayStatus(url, env);
            }

            if (request.method === 'GET' && path === '/v1/relay/credit') {
                await authorizeRequest(request, env, '');
                return await handleCredit(url, env);
            }

            if (request.method === 'POST' && path === '/v1/images/direct-upload') {
                const rawBody = await request.text();
                await authorizeRequest(request, env, rawBody);
                return await handleDirectImageUpload(rawBody, env);
            }

            if (request.method === 'GET' && path === '/v1/account/singleton-version') {
                return handleSingletonVersion(url, env);
            }

            if (request.method === 'POST' && path === '/v1/faucet/fund') {
                const rawBody = await request.text();
                await authorizeRequest(request, env, rawBody);
                return await handleFaucetFund(rawBody, env, ctx);
            }

            if (request.method === 'POST' && path.startsWith('/v1/webhook/fill-ready/')) {
                return await handleWebhookFillReady(request, env);
            }

            return jsonResponse({ ok: false, error: 'not_found' }, 404);
        } catch (error) {
            if (error instanceof AuthError) {
                return jsonResponse(
                    { ok: false, error: 'unauthorized', reason: error.message },
                    401,
                );
            }
            if (error instanceof BadRequestError) {
                return jsonResponse(
                    { ok: false, error: 'bad_request', reason: error.message },
                    400,
                );
            }
            if (error instanceof PaymentRequiredError) {
                return jsonResponse(
                    {
                        ok: false,
                        error: 'payment_required',
                        account: error.account,
                        supportMode: error.supportMode,
                        estimatedDebitNative: formatNativeToken(error.estimatedDebitWei),
                        balanceNative: formatNativeToken(error.balanceWei),
                        postDebitNative: formatNativeToken(error.postDebitWei),
                        minimumAllowedNative: formatNativeToken(error.minimumAllowedWei),
                        requiredTopUpNative: formatNativeToken(error.requiredTopUpWei),
                        suggestedTopUpNative: formatNativeToken(error.suggestedTopUpWei),
                        paymentOptions: error.paymentOptions,
                    },
                    402,
                );
            }

            const reason = error instanceof Error ? error.message : 'internal_error';
            return jsonResponse({ ok: false, error: 'internal_error', reason }, 500);
        }
    },

    async queue(
        batch: MessageBatch<RelayQueueMessage | AlertQueueMessage>,
        env: Env,
    ): Promise<void> {
        switch (batch.queue) {
            case 'relay-batch-queue':
                await consumeRelayBatch(batch as MessageBatch<RelayQueueMessage>, env);
                break;
            case 'alerts-queue':
                await consumeAlertsBatch(batch as MessageBatch<AlertQueueMessage>, env);
                break;
            default:
                console.error(`[queue] Unknown queue: ${batch.queue}`);
                break;
        }
    },

    async scheduled(_event: ScheduledEvent, env: Env, _ctx: ExecutionContext): Promise<void> {
        await sweepDeferredIntents(env);
    },
};

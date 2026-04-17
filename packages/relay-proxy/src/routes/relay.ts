/**
 * Relay route — submits ERC-4337 UserOperations to Gelato bundlers on
 * behalf of the caller, charging the cost against their gas tank.
 *
 * ## Middleware pipeline
 *
 * `zValidator → auth(high) → validateRelaySender → chainPolicy → quoteToken → handler`
 *
 * By the time the handler runs, the request is fully validated, the caller
 * is authenticated with a high-fidelity App Attest assertion, the sender
 * address has been verified against the session, every referenced chain is
 * known/enabled, and Gelato fee quotes are pre-computed.
 *
 * ## Gas accounting lifecycle
 *
 * 1. **Reserve** — `admitExposure` atomically increments pending exposure
 *    in the {@link GasAccountDurableObject}. If balance + overdraft headroom
 *    is insufficient, the DO rejects the request.
 * 2. **Send** — UserOperations are submitted. On failure, pending exposure
 *    is rolled back and (for plans) the deferred intent-execution record
 *    is deleted.
 * 3. **Settle** — Three concurrent writes fire after a successful send:
 *    - `incrementOutstandingDebt` — moves from "pending" to "owed" in D1.
 *    - `decrementPendingExposure` — releases admitted pending exposure.
 *    - `incrementUsage` — records per-chain spend in KV for history.
 *    If any of these fail, the relay still succeeds (the UserOp is on-chain),
 *    but the failures are logged as an anomaly for operator attention.
 *
 * ## Rooted Execution Model (Strategies)
 *
 * This proxy enforces a strictly rooted array architecture:
 * - **immediate**: The synchronous bootstrap boundary (e.g. creating the counterfactual wallet). This fails fast if the provider rejects the payload.
 * - **background**: Zero or more subsequent execution steps that fire blindly in parallel natively via `Promise.all` *after* the immediate block resolves.
 * - **deferred**: Stores a single payload in Cloudflare KV via Goldsky to be executed in the future natively upon remote event completion.
 *
 * @module
 */
import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';

import { auth } from '@/middleware/auth-handler';
import { chainPolicy } from '@/middleware/chain-policy';
import { quoteToken } from '@/middleware/quote-token';
import { validateRelaySender } from '@/schemas/relay';
import { relaySubmitSchema, rpcHook } from '@/schemas/rpc';
import { createBundlerClient } from '@/services/bundler';
import { createGasClient } from '@/services/gas';
import { createGasProfileStore, createGasUsageStore } from '@/stores/gas';
import type {
    AppBindings,
    CreateAppOptions,
    GasUsageBucketRecord,
    RelayDeferredResult,
    RelaySubmitResult,
    SendUserOperationBatchResult,
    SupportedChainId,
} from '@/types';
import { getAnomalyLogger, getChainConfig, getGasChain, rpcError, rpcResult, toRelayOperations, uint } from '@/utils';
import { deleteIntentExecution, storeIntentExecution } from '@/workers';
import { validator } from 'hono/validator';
import { Hex, RpcUserOperationReceipt } from 'viem';

export function createRelayRoutes(options: CreateAppOptions = {}) {
    const routes = new Hono<AppBindings>();

    routes.post(
        '/submit',
        zValidator('json', relaySubmitSchema, rpcHook),
        auth('high', options),
        validator('json', validateRelaySender),
        chainPolicy(options),
        quoteToken(),
        async (c) => {
            const rpc = c.req.valid('json');
            const chain = c.get('chain');
            const session = c.get('session');
            const quotes = c.get('quotes');

            const [operations, entryPoint] = rpc.params.request;
            const ops = toRelayOperations(operations);

            const gasChain = getGasChain(getChainConfig(ops.first.chainId).environment);
            const gasClient = createGasClient(c.env, await createBundlerClient(c.env, gasChain, options), options);
            const gasProfileStore = createGasProfileStore(c.env);
            const usageStore = createGasUsageStore(c.env);

            const ctx = await gasClient.ctx(session.userId, gasProfileStore);

            try {
                const charge = uint.add(...Object.values(quotes).map((q) => uint(q.fee)));
                await gasClient.admitExposure(session.userId, ctx.balanceUsdc, charge);

                const { immediate, deferred, backgroundCalls, usageCalls } = await (async () => {
                    let immediate: RpcUserOperationReceipt | undefined;
                    let backgroundCalls: [SupportedChainId, () => Promise<Hex>][] = [];
                    let deferred: RelayDeferredResult | undefined;
                    let usageCalls: (() => Promise<GasUsageBucketRecord>)[] = [];

                    if (!!rpc.params.fillId) {
                        // try to store the deffered operation or fail fast.
                        deferred = await storeIntentExecution(c.env, {
                            fillId: rpc.params.fillId,
                            request: rpc.params.request,
                        });
                    }

                    await Promise.all(
                        ops.map(async (op) => {
                            const { chainId, userOp } = op.unwrap();
                            const bundlerClient = await chain[chainId].client;

                            switch (op.strategy) {
                                case 'deferred':
                                    return;
                                case 'immediate':
                                    try {
                                        // Point of no return: once the immediate operation is processed on-chain, this plan is non reversible.
                                        immediate = await bundlerClient.sendUserOperationSync(userOp, entryPoint);
                                    } catch (e) {
                                        await gasClient.decrementPendingExposure(session.userId, charge);
                                        if (deferred) {
                                            await deleteIntentExecution(c.env, deferred.fillId);
                                        }
                                        throw e;
                                    }
                                    break;
                                case 'background':
                                    backgroundCalls.push([
                                        chainId,
                                        () => bundlerClient.sendUserOperation(userOp, entryPoint),
                                    ]);
                                    break;
                            }
                            usageCalls.push(() =>
                                usageStore.incrementUsage(session.userId, chainId, uint(quotes[chainId].fee)),
                            );
                        }),
                    );

                    return { immediate, backgroundCalls, deferred, usageCalls };
                })();

                const background = (await Promise.all(
                    backgroundCalls.map(([chainId, call]) =>
                        call()
                            .then((hash) => {
                                return { chainId, ok: true as const, hash };
                            })
                            .catch((error) => {
                                return { chainId, ok: false as const, error: error.message };
                            }),
                    ),
                )) satisfies SendUserOperationBatchResult[];

                const result: RelaySubmitResult = {
                    ...(background.length > 0 && { background }),
                    ...(immediate && { immediate }),
                    ...(deferred && { deferred }),
                };

                const accounting = await Promise.allSettled([
                    gasClient.incrementOutstandingDebt(session.userId, charge),
                    gasClient.decrementPendingExposure(session.userId, charge),
                    ...usageCalls.map((fn) => fn()),
                ]);

                const failures = accounting.flatMap((a) => (a.status === 'rejected' ? [a.reason] : []));
                if (failures.length > 0) {
                    console.error('[relay-gas-accounting] failed', failures);
                    const logAnomaly = getAnomalyLogger(c.env, '*');
                    logAnomaly({
                        chargeUsdc: charge.hex,
                        failures,
                        type: 'anomaly_relay_gas_accounting_failed',
                        userId: session.userId,
                    });
                }

                return c.json(rpcResult(rpc.id, result));
            } catch (error) {
                const isUpstream = error instanceof Error && 'code' in error;
                const message = error instanceof Error ? error.message : 'Internal error';

                if (!isUpstream) return rpcError(c, rpc.id, -32603, message);
                throw error;
            }
        },
    );

    return routes;
}

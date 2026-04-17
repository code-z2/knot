/**
 * Gas-tank RPC routes — balance, history, overdraft management, and
 * cosigned withdrawals.
 *
 * Every gas endpoint requires at least a `low`-fidelity session (bearer
 * token). State-changing operations (`overdraft`, `withdraw`) require
 * `high` fidelity (App Attest assertion).
 *
 * ## Route summary
 *
 * | Endpoint       | Method                     | Auth  | Purpose                                               |
 * |----------------|----------------------------|-------|-------------------------------------------------------|
 * | `/`            | `knot_gasStatus`           | low   | Current balance, overdraft state, provider address    |
 * | `/history`     | `knot_gasHistory`          | low   | Rolling-window per-chain spend from KV buckets        |
 * | `/overdraft`   | `knot_gasOverdraftUpdate`  | high  | Enable/disable overdraft (if eligible and not locked) |
 * | `/withdraw`    | `knot_gasWithdraw`         | high  | Collect debt, then cosign a withdrawal for the user   |
 *
 * ## Withdraw lifecycle
 *
 * The `/withdraw` handler first attempts to **collect** outstanding debt
 * by encoding a `GasTank.debit()` UserOperation and submitting it
 * on-chain. Only the remainder after collection is available for
 * withdrawal. If any debt remains uncollected, or if there's nothing
 * left to withdraw, the request is rejected with `pending_debit_outstanding`.
 *
 * @module
 */
import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';

import { RPC_APP_ERRORS } from '@/errors';
import { auth } from '@/middleware/auth-handler';
import { gasHistorySchema, gasOverdraftUpdateSchema, gasStatusSchema, gasWithdrawSchema, rpcHook } from '@/schemas/rpc';
import { createBundlerClient } from '@/services/bundler';
import { createGasClient } from '@/services/gas';

import { createGasProfileStore, createGasUsageStore } from '@/stores/gas';
import type { AppBindings, CreateAppOptions } from '@/types';
import { getGasChain, rpcAppError, rpcError, rpcResult, uint } from '@/utils';
import { executeCalls } from '@/services/account';

export function createGasRoutes(options: CreateAppOptions = {}) {
    const routes = new Hono<AppBindings>();

    routes.post('/', zValidator('json', gasStatusSchema, rpcHook), auth('low', options), async (c) => {
        const rpc = c.req.valid('json');
        const session = c.get('session');
        const gasProfileStore = createGasProfileStore(c.env);
        const gasProfile = await gasProfileStore.getGasProfile(session.userId);
        const gasChain = getGasChain(rpc.params.environment ?? 'mainnet');
        try {
            const bundler = await createBundlerClient(c.env, gasChain, options);
            const gasClient = createGasClient(c.env, bundler, options);
            const balanceUsdc = uint(await gasClient.getGasBalance(session.userId));
            const { outstandingDebtUsdc: _, updatedAt: __, userId: ___, ...rest } = gasProfile;
            const result = {
                balanceUsdc,
                ...rest,
                provider: gasClient.getGasProvider(session.userId),
            };

            return c.json(rpcResult(rpc.id, result));
        } catch (error) {
            const message = error instanceof Error ? error.message : 'Internal error';
            return rpcError(c, rpc.id, -32603, message, 500);
        }
    });

    routes.post('/history', zValidator('json', gasHistorySchema, rpcHook), auth('low', options), async (c) => {
        const rpc = c.req.valid('json');
        const session = c.get('session');
        const window = rpc.params.window ?? '3m';
        const usage = await createGasUsageStore(c.env).getUsageHistory(session.userId, window);

        return c.json(
            rpcResult(rpc.id, {
                ...usage,
                window,
            }),
        );
    });

    routes.post(
        '/overdraft',
        zValidator('json', gasOverdraftUpdateSchema, rpcHook),
        auth('high', options),
        async (c) => {
            const rpc = c.req.valid('json');
            const session = c.get('session');
            const gasProfileStore = createGasProfileStore(c.env);
            const now = Date.now();
            const gasProfile = await gasProfileStore.getGasProfile(session.userId);

            let response: Response;

            switch (rpc.params.action) {
                case 'enable': {
                    if (!gasProfile.overdraftEligible) {
                        return rpcAppError(c, rpc.id, RPC_APP_ERRORS.overdraftNotEligible);
                    }

                    const next = await gasProfileStore.updateGasProfile({
                        ...gasProfile,
                        overdraftEnabled: true,
                        updatedAt: now,
                    });

                    const { outstandingDebtUsdc: _, updatedAt: __, userId: ___, ...rest } = next;

                    response = c.json(rpcResult(rpc.id, rest));
                    break;
                }
                case 'disable':
                default: {
                    if (gasProfile.overdraftLocked || !uint.isZero(gasProfile.overdraftOutstandingUsdc)) {
                        return rpcAppError(c, rpc.id, RPC_APP_ERRORS.overdraftLocked);
                    }

                    const next = await gasProfileStore.updateGasProfile({
                        ...gasProfile,
                        overdraftEnabled: false,
                        updatedAt: now,
                    });

                    const { outstandingDebtUsdc: _, updatedAt: __, userId: ___, ...rest } = next;

                    response = c.json(rpcResult(rpc.id, rest));
                }
            }

            return response;
        },
    );

    routes.post('/withdraw', zValidator('json', gasWithdrawSchema, rpcHook), auth('high', options), async (c) => {
        const rpc = c.req.valid('json');
        const session = c.get('session');
        const gasChain = getGasChain(rpc.params.environment ?? 'mainnet');
        const gasProfileStore = createGasProfileStore(c.env);

        try {
            const bundler = await createBundlerClient(c.env, gasChain, options);
            const gasClient = createGasClient(c.env, bundler, options);
            const ctx = await gasClient.ctx(session.userId, gasProfileStore);

            if (ctx.gasProfile.overdraftLocked) {
                return rpcAppError(c, rpc.id, RPC_APP_ERRORS.overdraftLocked);
            }

            if (ctx.provider.kind !== 'knot') {
                return rpcAppError(c, rpc.id, RPC_APP_ERRORS.gasProviderUnsupported);
            }

            const collectibleUsdc = uint.min(ctx.gasProfile.outstandingDebtUsdc, ctx.balanceUsdc);

            if (!uint.isZero(collectibleUsdc)) {
                const calls = await gasClient.encodeDebitCall(session.userId, collectibleUsdc);

                await executeCalls(bundler, calls);
                await gasClient.decrementOutstandingDebt(session.userId, collectibleUsdc);
            }

            const withdrawAmount = uint.sub(ctx.balanceUsdc, collectibleUsdc);
            const remainingDebt = uint.sub(ctx.gasProfile.outstandingDebtUsdc, collectibleUsdc);

            if (!uint.isZero(remainingDebt) || uint.isZero(withdrawAmount)) {
                return rpcAppError(c, rpc.id, RPC_APP_ERRORS.pendingDebitOutstanding);
            }

            const nonce = await gasClient.getGasWithdrawalNonce(session.userId);
            const cosignerSig = await gasClient.cosign(session.userId, {
                amount: withdrawAmount,
                deadline: rpc.params.deadline,
                to: rpc.params.to,
            });

            return c.json(
                rpcResult(rpc.id, {
                    amount: withdrawAmount,
                    cosignerSig,
                    gasTankAddress: ctx.provider.gasTankAddress,
                    nonce: uint(nonce).hex,
                }),
            );
        } catch (error) {
            const message = error instanceof Error ? error.message : 'Internal error';
            return rpcError(c, rpc.id, -32603, message, 500);
        }
    });

    return routes;
}

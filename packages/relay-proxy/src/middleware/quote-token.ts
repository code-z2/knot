/**
 * Quote-token middleware — fetches Gelato fee quotes for every active UserOperation
 * in the flattened relay array before the route handler runs.
 *
 * Quotes are strictly required because the relay handler bounds the user's gas-tank
 * exposure (via the {@link GasAccountDurableObject}) using the exact computed USDC
 * sum of all executed operations.
 *
 * The middleware isolates simulation and quoting to `immediate` and `background`
 * strategies only, running fetch requests heavily in parallel via `Promise.all`.
 * `deferred` operations are structurally skipped because they execute against future
 * state (which cannot be meaningfully or reliably quoted at the time of initial root submission).
 *
 * The middleware reads the {@link ChainPolicyContext} set by `chainPolicy`
 * and awaits each chain's already-warming bundler client promise rather than
 * creating new disjoint clients.
 *
 * On success, the computed quotes are stored in the Hono context as
 * {@link RelayQuoteContext} so the reserved handler can charge accurate fiat amounts.
 *
 * @module
 */
import type { MiddlewareHandler } from 'hono';

import { RPC_APP_ERRORS } from '@/errors/catalog';
import { RelaySubmitInput } from '@/schemas/rpc';
import type { AppBindings, RelayQuoteContext } from '@/types';
import { rpcAppError, toRelayOperations } from '@/utils';

/**
 * Fetch Gelato fee quotes for all operations in the relay request.
 *
 * Expects `chainPolicy` to have already set `c.get('chain')` with
 * validated chain configs and their bundler client promises.
 *
 * @throws Wrapped as `bundlerNotConfigured` RPC error if any quote fetch
 *   fails — this catches both bundler client init failures and Gelato API
 *   errors in a single catch-all.
 */
export function quoteToken(): MiddlewareHandler<AppBindings, string, RelaySubmitInput> {
    return async (c, next) => {
        const rpc = c.req.valid('json');
        const chain = c.get('chain');

        const [operations, entryPoint] = rpc.params.request;
        const ops = toRelayOperations(operations);

        try {
            const quotes = await Promise.all(
                ops
                    .filter((op) => op.strategy !== 'deferred')
                    .map(async (op) => {
                        const { chainId, userOp } = op.unwrap();
                        const bundlerClient = await chain[chainId].client;
                        const quote = await bundlerClient.getUserOperationQuote(userOp, entryPoint);
                        return [chainId, quote] as const;
                    }),
            );

            c.set('quotes', Object.fromEntries(quotes));
            await next();
        } catch {
            return rpcAppError(c, rpc.id, RPC_APP_ERRORS.bundlerNotConfigured);
        }
    };
}

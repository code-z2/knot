/**
 * Chain policy middleware — validates that every chain referenced in a relay
 * request is both supported and enabled, and that the entry point is accepted
 * by all of them.
 *
 * ## Architecture Boundary
 *
 * This runs **after** zod schema validation. Zod is strictly responsible for
 * *structural shape validation* (e.g., "is it an integer?", "does it follow the protocol?").
 * This middleware manages the *runtime policy boundary* (e.g., "is this chain supported
 * in this environment?", "is the entry point valid for this chain config?"), keeping
 * validation concerns decoupled.
 *
 * On success, the middleware builds a {@link ChainPolicyContext} mapping each
 * validated chain ID to its config **and initiates a lazily-resolving bundler client
 * promise**. This lets downstream middleware (`quoteToken`) natively `await` the
 * warming client without duplicating heavy API initialization parameters.
 *
 * @module
 */
import type { MiddlewareHandler } from 'hono';

import { invalidParams } from '@/errors/catalog';
import { RelaySubmitInput } from '@/schemas/rpc';
import { createBundlerClient } from '@/services/bundler';
import type { AppBindings, ChainPolicyContext, CreateAppOptions } from '@/types';
import {
    getChainConfig,
    getEntryPointFromRequest,
    isSupportedEntryPoints,
    rpcAppError,
    toRelayOperations,
} from '@/utils';

/**
 * Gate relay requests on chain support, enablement, and entry point validity.
 *
 * The middleware pipeline for `/relay/submit` is:
 * `zValidator → auth(high) → validateRelaySender → chainPolicy → quoteToken → handler`
 *
 * @param options - Forwarded to `createBundlerClient` so tests can inject
 *   a mock bundler.
 */
export function chainPolicy(options: CreateAppOptions = {}): MiddlewareHandler<AppBindings, string, RelaySubmitInput> {
    return async (c, next) => {
        const rpc = c.req.valid('json');

        const { id: rpcId, params } = rpc;

        const ops = toRelayOperations(params.request[0]);

        const configs = ops.map((op) => getChainConfig(op.unwrap().chainId));

        if (configs.some((config) => !config.enabled)) {
            return rpcAppError(c, rpcId, invalidParams('request.0..chainId'));
        }

        const entryPoint = getEntryPointFromRequest(params.request);

        if (entryPoint == null || !isSupportedEntryPoints(configs, entryPoint)) {
            return rpcAppError(c, rpcId, invalidParams('params.request.1'));
        }

        const chainPolicy = configs.reduce((acc, config) => {
            const client = createBundlerClient(c.env, config, options);
            acc[config.id] = { client, config };
            return acc;
        }, {} as ChainPolicyContext);

        c.set('chain', chainPolicy);
        await next();
    };
}

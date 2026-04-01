import type { MiddlewareHandler } from 'hono';

import { RPC_APP_ERRORS } from '@/errors/catalog';
import { createBundlerClient } from '@/services/bundler';
import type { AppBindings, RelaySubmitParams, RpcId } from '@/types';
import { rpcAppError } from '@/utils';

export function quoteToken(
    client: typeof createBundlerClient = createBundlerClient,
): MiddlewareHandler<AppBindings> {
    return async (c, next) => {
        const rpc = (c.req.valid as (target: 'json') => { id: RpcId; params: RelaySubmitParams })(
            'json',
        );
        const chain = c.get('chain');
        const bundlerApiKey = c.env.BUNDLER_API_KEY;
        const jsonRpcApiKey = c.env.JSON_RPC_API_KEY;

        if (!bundlerApiKey) {
            return rpcAppError(c, rpc.id, RPC_APP_ERRORS.bundlerNotConfigured);
        }

        try {
            const bundlerClient = client({ chain, bundlerApiKey, jsonRpcApiKey });

            if (rpc.params.kind === 'single') {
                const [userOperation, entryPoint] = rpc.params.request;
                const quote = await bundlerClient.getUserOperationQuote(userOperation, entryPoint);

                c.set('relayQuote', {
                    kind: 'single',
                    quote,
                });
                await next();
                return;
            }

            const [operations, entryPoint] = rpc.params.request;
            const immediateQuote = operations.immediate
                ? await bundlerClient.getUserOperationQuote(operations.immediate, entryPoint)
                : undefined;
            const backgroundQuotes = await Promise.all(
                operations.background.map((userOperation) =>
                    bundlerClient.getUserOperationQuote(userOperation, entryPoint),
                ),
            );

            c.set('relayQuote', {
                backgroundQuotes,
                immediateQuote,
                kind: 'plan',
            });
            await next();
        } catch {
            return rpcAppError(c, rpc.id, RPC_APP_ERRORS.bundlerNotConfigured);
        }
    };
}

import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';

import { auth } from '@/middleware/auth-handler';
import { chainPolicy } from '@/middleware/chain-policy';
import { quoteToken } from '@/middleware/quote-token';
import { validateRelaySender } from '@/schemas/relay';
import { relaySubmitSchema, rpcHook } from '@/schemas/rpc';
import { createBundlerClient } from '@/services/bundler';
import type {
    AppBindings,
    BundlerClient,
    CreateAppOptions,
    RelayPlanParams,
    RelaySingleParams,
    RelaySubmitResult,
} from '@/types';
import { rpcError, rpcResult } from '@/utils';
import { storeIntentExecution } from '@/workers';
import { validator } from 'hono/validator';

export function createRelayRoutes(options: CreateAppOptions = {}) {
    const routes = new Hono<AppBindings>();

    const executePlan = async (
        env: AppBindings['Bindings'],
        bundlerClient: BundlerClient,
        params: RelayPlanParams,
    ): Promise<RelaySubmitResult> => {
        const [operations, entryPoint] = params.request;

        const immediateReceipt = operations.immediate
            ? await bundlerClient.sendUserOperationSync(operations.immediate, entryPoint)
            : undefined;

        const backgroundResults = await bundlerClient.sendUserOperationBatch(
            [...operations.background],
            entryPoint,
        );

        const deferred = await storeIntentExecution(env, params);

        return {
            kind: 'plan',
            backgroundResults,
            ...(immediateReceipt && { immediateReceipt }),
            ...(deferred && { deferred }),
        };
    };

    routes.post(
        '/submit',
        zValidator('json', relaySubmitSchema, rpcHook),
        auth('high', options),
        validator('json', validateRelaySender),
        chainPolicy(),
        quoteToken(options),
        async (c) => {
            const rpc = c.req.valid('json');
            const chain = c.get('chain');
            const bundlerClient = createBundlerClient(c.env, chain, options);

            try {
                let result: RelaySubmitResult;
                switch (rpc.params.kind) {
                    case 'plan':
                        result = await executePlan(c.env, bundlerClient, rpc.params);
                        break;
                    case 'single':
                    default: {
                        const _exhaustive: RelaySingleParams = rpc.params;
                        const [userOperation, entryPoint] = _exhaustive.request;
                        result = {
                            kind: 'single',
                            userOperationHash: await bundlerClient.sendUserOperation(
                                userOperation,
                                entryPoint,
                            ),
                        };
                    }
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

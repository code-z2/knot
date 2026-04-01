import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';

import { rpcHook, supportedChainsSchema } from '@/schemas/rpc';
import type { AppBindings } from '@/types';
import { getSupportedChains, rpcResult, toPublicChainDescriptor } from '@/utils';

export function createChainRoutes() {
    const routes = new Hono<AppBindings>();

    routes.post('/', zValidator('json', supportedChainsSchema, rpcHook), (c) => {
        const rpc = c.req.valid('json');
        const chains = getSupportedChains(rpc.params.environment).map(toPublicChainDescriptor);

        return c.json(
            rpcResult(rpc.id, {
                chains,
            }),
        );
    });

    return routes;
}

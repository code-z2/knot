import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';

import { RPC_APP_ERRORS } from '@/errors';
import { auth } from '@/middleware/auth-handler';
import { faucetRequestSchema, rpcHook } from '@/schemas/rpc';
import { createFaucetStore } from '@/stores/faucet';
import type { AppBindings, CreateAppOptions, FaucetDOResult } from '@/types';
import { doRequestHandler, rpcAppError, rpcResult } from '@/utils';

export function createFaucetRoutes(options: CreateAppOptions = {}) {
    const routes = new Hono<AppBindings>();

    routes.post('/request', zValidator('json', faucetRequestSchema, rpcHook), auth('low', options), async (c) => {
        const rpc = c.req.valid('json');
        const session = c.get('session');
        const store = createFaucetStore(c.env);

        if (await store.hasConsumed(session.userId)) {
            return rpcAppError(c, rpc.id, RPC_APP_ERRORS.faucetAlreadyConsumed);
        }

        const makeDORequest = doRequestHandler(c.env, 'FAUCET_DO');

        const result = await makeDORequest<FaucetDOResult>(session.userId, '/request', {
            method: 'POST',
        });

        return c.json(rpcResult(rpc.id, result));
    });

    return routes;
}

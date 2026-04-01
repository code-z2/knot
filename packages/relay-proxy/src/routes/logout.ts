import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';

import { auth } from '@/middleware/auth-handler';
import { rpcHook, userLogoutSchema } from '@/schemas/rpc';
import { createAuthClient } from '@/services/auth';
import { revokeSession } from '@/services/session';
import type { AppBindings, CreateAppOptions } from '@/types';
import { rpcResult } from '@/utils';

/**
 * Logout uses low-fidelity auth by design. A valid session can always revoke
 * itself without requiring a fresh App Attest assertion.
 */
export function createUserLogoutRoutes(options: CreateAppOptions = {}) {
    const routes = new Hono<AppBindings>();

    routes.post(
        '/',
        zValidator('json', userLogoutSchema, rpcHook),
        auth('low', options),
        async (c) => {
            const rpc = c.req.valid('json');
            const session = c.get('session');

            const client = createAuthClient(c.env, options);
            await revokeSession(client.store, session.accessToken);

            return c.json(
                rpcResult(rpc.id, {
                    loggedOut: true,
                    sessionId: session.id,
                    userId: session.userId,
                }),
            );
        },
    );

    return routes;
}

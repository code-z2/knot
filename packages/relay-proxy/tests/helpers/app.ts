import { zValidator } from '@hono/zod-validator';
import { createApp } from '../../src/app';
import { auth } from '../../src/middleware/auth-handler';
import { rpcHook, userLogoutSchema } from '../../src/schemas/rpc';
import type { CreateAppOptions } from '../../src/types';
import { rpcResult } from '../../src/utils';
import { createTestAuth } from '../fixtures/test-auth';
import { createTestUpload } from '../fixtures/test-upload';

export function createTestApp(options: CreateAppOptions = {}) {
    const authConfig = options.auth ?? createTestAuth();
    const uploadConfig = options.upload ?? createTestUpload();
    const app = createApp({
        ...options,
        auth: authConfig,
        upload: uploadConfig,
    });

    return {
        app,
        auth: authConfig,
        upload: uploadConfig,
    };
}

export function attachHighFidelityTestRoute(
    app: ReturnType<typeof createTestApp>['app'],
    options: CreateAppOptions,
) {
    app.post(
        '/v1/protected/high',
        zValidator('json', userLogoutSchema, rpcHook),
        auth('high', options),
        (c) => {
            const rpc = c.req.valid('json');
            const session = c.get('session');

            return c.json(
                rpcResult(rpc.id, {
                    ok: true,
                    userId: session.userId,
                }),
            );
        },
    );
}

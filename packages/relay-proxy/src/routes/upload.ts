import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';

import { RPC_APP_ERRORS } from '@/errors';
import { auth } from '@/middleware/auth-handler';
import { imageUploadOptionsSchema, rpcHook } from '@/schemas/rpc';
import { createUploadClient } from '@/services/pinata';
import { issueImageUploadOptions } from '@/services/upload';
import type { AppBindings, CreateAppOptions } from '@/types';
import { rpcAppError, rpcResult } from '@/utils';

/**
 * Upload V1 only issues signed direct-upload URLs. It does not proxy file bytes
 * or persist upload rows on the backend.
 */
export function createUploadRoutes(options: CreateAppOptions = {}) {
    const routes = new Hono<AppBindings>();

    routes.post(
        '/image/options',
        zValidator('json', imageUploadOptionsSchema, rpcHook),
        auth('low', options),
        async (c) => {
            const rpc = c.req.valid('json');
            const session = c.get('session');
            const upload = createUploadClient(c.env, options);

            const result = await issueImageUploadOptions(upload, {
                ...rpc.params,
                userId: session.userId,
            });

            if (!result.ok && result.error) {
                return rpcAppError(
                    c,
                    rpc.id,
                    result.error === 'upload_unavailable'
                        ? RPC_APP_ERRORS.uploadUnavailable
                        : RPC_APP_ERRORS.fileTooLarge,
                );
            }

            return c.json(rpcResult(rpc.id, result.result));
        },
    );

    return routes;
}

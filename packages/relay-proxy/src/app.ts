import { Hono } from 'hono';

import { createUserLoginRoutes } from '@/routes/login';
import { createUserLogoutRoutes } from '@/routes/logout';
import { createUserRegisterRoutes } from '@/routes/register';
import { createUploadRoutes } from '@/routes/upload';
import type { AppBindings, CreateAppOptions } from '@/types';

export function createApp(options: CreateAppOptions = {}) {
    const app = new Hono<AppBindings>();

    app.get('/', (c) => {
        return c.json({
            ok: true,
            rpc: true,
            service: 'relay-proxy',
            version: 1,
        });
    });

    app.get('/health', (c) => {
        return c.json({
            ok: true,
            framework: 'hono',
            runtime: 'cloudflare-workers',
            service: 'relay-proxy',
        });
    });

    app.route('/v1/user/register', createUserRegisterRoutes(options));
    app.route('/v1/user/login', createUserLoginRoutes(options));
    app.route('/v1/user/logout', createUserLogoutRoutes(options));
    app.route('/v1/upload', createUploadRoutes(options));

    app.notFound((c) => {
        return c.json(
            {
                ok: false,
                error: 'not_found',
            },
            404,
        );
    });

    return app;
}

const app = createApp();

export default app;

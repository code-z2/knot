/**
 * Hono application factory and route topology.
 *
 * Every route group is mounted under `/v1/` and receives the same
 * {@link CreateAppOptions} bag, which lets tests swap the bundler, gas
 * client, auth runtime, or upload client with in-memory fakes without
 * touching any Cloudflare bindings.
 *
 * A bare `createApp()` call (no options) produces the production app,
 * which is default-exported for the Worker `fetch` handler.
 *
 * @module
 */
import { Hono } from 'hono';

import { SUPPORTED_RPC_METHODS } from '@/constants';
import { createChainRoutes } from '@/routes/chains';
import { createGasRoutes } from '@/routes/gas';
import { createUserLoginRoutes } from '@/routes/login';
import { createUserLogoutRoutes } from '@/routes/logout';
import { createRelayRoutes } from '@/routes/relay';
import { createUserRegisterRoutes } from '@/routes/register';
import { createUploadRoutes } from '@/routes/upload';
import type { AppBindings, CreateAppOptions } from '@/types';

/**
 * Build a Hono app with optional production-dependency overrides.
 *
 * Route layout:
 * ```
 * /v1/user/register  — WebAuthn passkey registration
 * /v1/user/login     — WebAuthn passkey authentication
 * /v1/user/logout    — Session revocation
 * /v1/chains         — Public chain metadata
 * /v1/gas            — Gas tank balance, history, overdraft, withdraw
 * /v1/relay          — Submit ERC-4337 UserOperations (single or plan)
 * /v1/upload         — Signed image-upload URLs (Pinata)
 * ```
 *
 * @param options - Override production dependencies for testing.
 *   Omit entirely in production; the Worker entrypoint calls `createApp()`
 *   with no arguments.
 */
export function createApp(options: CreateAppOptions = {}) {
    const app = new Hono<AppBindings>();

    app.get('/', (c) => {
        return c.json({
            ok: true,
            rpc: true,
            service: 'relay-proxy',
            supportedMethods: SUPPORTED_RPC_METHODS,
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
    app.route('/v1/chains', createChainRoutes());
    app.route('/v1/gas', createGasRoutes(options));
    app.route('/v1/relay', createRelayRoutes(options));
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

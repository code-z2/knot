import { describe, expect, it } from 'bun:test';

import { SUPPORTED_RPC_METHODS } from '@/constants';
import { createTestApp } from './helpers/app';
import { readJson } from './helpers/http';

describe('relay proxy app routes', () => {
    it('serves the root route', async () => {
        const { app } = createTestApp();
        const response = await app.request('http://localhost/');

        expect(response.status).toBe(200);
        expect(
            await readJson<{
                ok: boolean;
                rpc: boolean;
                service: string;
                supportedMethods: readonly string[];
                version: number;
            }>(response),
        ).toEqual({
            ok: true,
            rpc: true,
            service: 'relay-proxy',
            supportedMethods: SUPPORTED_RPC_METHODS,
            version: 1,
        });
    });

    it('serves the health route', async () => {
        const { app } = createTestApp();
        const response = await app.request('http://localhost/health');

        expect(response.status).toBe(200);
        expect(
            await readJson<{
                ok: boolean;
                framework: string;
                runtime: string;
                service: string;
            }>(response),
        ).toEqual({
            ok: true,
            framework: 'hono',
            runtime: 'cloudflare-workers',
            service: 'relay-proxy',
        });
    });

    it('returns a json 404 for unknown routes', async () => {
        const { app } = createTestApp();
        const response = await app.request('http://localhost/unknown');

        expect(response.status).toBe(404);
        expect(
            await readJson<{
                error: string;
                ok: boolean;
            }>(response),
        ).toEqual({
            error: 'not_found',
            ok: false,
        });
    });
});

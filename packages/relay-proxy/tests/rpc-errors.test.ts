import { describe, expect, it } from 'bun:test';

import type { RpcFailure } from '../src/types';
import { createTestApp } from './helpers/app';
import { jsonHeaders, readJson } from './helpers/http';

describe('relay proxy rpc errors', () => {
    it('rejects a route and method mismatch', async () => {
        const { app } = createTestApp();
        const response = await app.request('http://localhost/v1/user/login/options', {
            method: 'POST',
            headers: jsonHeaders(),
            body: JSON.stringify({
                id: 'mismatch',
                jsonrpc: '2.0',
                method: 'knot_userLogout',
                params: {},
            }),
        });

        expect(response.status).toBe(400);
        const body = await readJson<RpcFailure>(response);

        expect(body.id).toBe('mismatch');
        expect(body.jsonrpc).toBe('2.0');
        expect(body.error.code).toBe(-32601);
        expect(body.error.message).toBe('method_not_allowed_for_route');
        expect(body.error.reason).toBe('method_not_allowed_for_route');
        expect(body.error.details).toEqual(
            expect.arrayContaining([
                {
                    message: expect.any(String),
                    path: 'method',
                },
            ]),
        );
    });

    it('rejects invalid rpc envelopes', async () => {
        const { app } = createTestApp();
        const response = await app.request('http://localhost/v1/user/register/options', {
            method: 'POST',
            headers: jsonHeaders(),
            body: JSON.stringify({
                id: 'invalid_rpc',
                jsonrpc: '1.0',
                method: 'knot_userRegisterOptions',
                params: {
                    userId: 'not-an-address',
                },
            }),
        });

        expect(response.status).toBe(400);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'invalid_rpc',
            jsonrpc: '2.0',
            error: {
                code: -32600,
                details: expect.arrayContaining([
                    {
                        message: expect.any(String),
                        path: 'jsonrpc',
                    },
                    {
                        message: expect.any(String),
                        path: 'params.userId',
                    },
                ]),
                message: 'invalid_jsonrpc_version',
                reason: 'invalid_jsonrpc_version',
            },
        });
    });
});

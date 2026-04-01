import { describe, expect, it } from 'bun:test';

import type { RpcFailure, RpcSuccess } from '../src/types';
import { createTestApp } from './helpers/app';
import { jsonHeaders, readJson } from './helpers/http';

describe('relay proxy chain list route', () => {
    it('returns all supported chains when no environment filter is provided', async () => {
        const { app } = createTestApp();

        const response = await app.request('http://localhost/v1/chains', {
            method: 'POST',
            headers: jsonHeaders(),
            body: JSON.stringify({
                id: 'chains_all',
                jsonrpc: '2.0',
                method: 'knot_supportedChains',
                params: {},
            }),
        });

        expect(response.status).toBe(200);
        const body = await readJson<
            RpcSuccess<{
                chains: Array<{
                    chainId: number;
                    environment: 'mainnet' | 'testnet';
                    name: string;
                }>;
            }>
        >(response);

        expect(body.id).toBe('chains_all');
        expect(body.result.chains).toHaveLength(5);
        expect(body.result.chains.some((chain) => chain.environment === 'mainnet')).toBe(true);
        expect(body.result.chains.some((chain) => chain.environment === 'testnet')).toBe(true);
    });

    it('filters supported chains to testnets', async () => {
        const { app } = createTestApp();

        const response = await app.request('http://localhost/v1/chains', {
            method: 'POST',
            headers: jsonHeaders(),
            body: JSON.stringify({
                id: 'chains_testnet',
                jsonrpc: '2.0',
                method: 'knot_supportedChains',
                params: {
                    environment: 'testnet',
                },
            }),
        });

        expect(response.status).toBe(200);
        const body = await readJson<
            RpcSuccess<{
                chains: Array<{
                    chainId: number;
                    environment: 'mainnet' | 'testnet';
                    name: string;
                }>;
            }>
        >(response);

        expect(body.result.chains).toHaveLength(3);
        expect(body.result.chains.every((chain) => chain.environment === 'testnet')).toBe(true);
    });

    it('rejects invalid environment values at the schema boundary', async () => {
        const { app } = createTestApp();

        const response = await app.request('http://localhost/v1/chains', {
            method: 'POST',
            headers: jsonHeaders(),
            body: JSON.stringify({
                id: 'chains_invalid_env',
                jsonrpc: '2.0',
                method: 'knot_supportedChains',
                params: {
                    environment: 'devnet',
                },
            }),
        });

        expect(response.status).toBe(400);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'chains_invalid_env',
            jsonrpc: '2.0',
            error: {
                code: -32602,
                details: [
                    {
                        message: expect.any(String),
                        path: 'params.environment',
                    },
                ],
                message: 'invalid_params:params.environment',
                reason: 'invalid_params:params.environment',
            },
        });
    });
});

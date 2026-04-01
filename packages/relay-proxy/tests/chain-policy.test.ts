import { zValidator } from '@hono/zod-validator';
import { describe, expect, it } from 'bun:test';
import type { Context } from 'hono';
import { Hono } from 'hono';
import { z } from 'zod';

import { chainPolicy } from '../src/middleware/chain-policy';
import { relaySubmitSchema, rpcHook } from '../src/schemas/rpc';
import type { AppBindings, RpcFailure, RpcSuccess } from '../src/types';
import {
    buildBundlerUrl,
    buildJsonRpcUrl,
    getChainConfig,
    getMainnetChains,
    getSupportedChains,
    getTestnetChains,
    rpcResult,
} from '../src/utils';
import { jsonHeaders, readJson } from './helpers/http';

const chainPolicySchema = z.object({
    id: z.union([z.string(), z.number(), z.null()]),
    jsonrpc: z.literal('2.0'),
    method: z.literal('knot_chainPolicyTest'),
    params: z.object({
        chainId: z.number().int(),
    }),
});

function createChainPolicyApp() {
    const app = new Hono<AppBindings>();

    app.post(
        '/v1/test/chains',
        zValidator('json', chainPolicySchema, rpcHook),
        chainPolicy(),
        (c: Context<AppBindings>) => {
            const rpc = (c.req.valid as (target: 'json') => z.infer<typeof chainPolicySchema>)(
                'json',
            );
            const chain = c.get('chain');

            return c.json(
                rpcResult(rpc.id, {
                    chainId: chain.id,
                    environment: chain.environment,
                    name: chain.name,
                }),
            );
        },
    );

    return app;
}

function createRelayChainPolicyApp() {
    const app = new Hono<AppBindings>();

    app.post(
        '/v1/test/relay',
        zValidator('json', relaySubmitSchema, rpcHook),
        chainPolicy(),
        (c: Context<AppBindings>) => {
            const rpc = (
                c.req.valid as (target: 'json') => {
                    id: string | number | null;
                    params: { chainId: number };
                }
            )('json');
            const chain = c.get('chain');

            return c.json(
                rpcResult(rpc.id, {
                    chainId: chain.id,
                    ok: true,
                }),
            );
        },
    );

    return app;
}

describe('relay proxy chain config', () => {
    it('resolves supported mainnet and testnet chains', () => {
        expect(getChainConfig(8453)?.environment).toBe('mainnet');
        expect(getChainConfig(84532)?.environment).toBe('testnet');
        expect(getChainConfig(999999)).toBeNull();
    });

    it('filters supported chains by environment', () => {
        expect(getMainnetChains().every((chain) => chain.environment === 'mainnet')).toBe(true);
        expect(getTestnetChains().every((chain) => chain.environment === 'testnet')).toBe(true);

        expect(getSupportedChains('mainnet')).toHaveLength(getMainnetChains().length);
        expect(getSupportedChains('testnet')).toHaveLength(getTestnetChains().length);
        expect(getSupportedChains()).toHaveLength(
            getMainnetChains().length + getTestnetChains().length,
        );
    });

    it('builds a json rpc url from chain id and api key', () => {
        expect(buildJsonRpcUrl(84532, 'secret')).toBe(
            'https://edge.goldsky.com/standard/evm/84532?secret=secret',
        );
    });

    it('builds a sponsored bundler url from chain id', () => {
        expect(buildBundlerUrl(84532)).toBe('https://api.gelato.cloud/rpc/84532?payment=sponsored');
    });
});

describe('relay proxy chain policy middleware', () => {
    it('attaches a supported chain to the request context', async () => {
        const app = createChainPolicyApp();

        const response = await app.request('http://localhost/v1/test/chains', {
            method: 'POST',
            headers: jsonHeaders(),
            body: JSON.stringify({
                id: 'chain_supported',
                jsonrpc: '2.0',
                method: 'knot_chainPolicyTest',
                params: {
                    chainId: 84532,
                },
            }),
        });

        expect(response.status).toBe(200);
        expect(
            await readJson<RpcSuccess<{ chainId: number; environment: string; name: string }>>(
                response,
            ),
        ).toEqual({
            id: 'chain_supported',
            jsonrpc: '2.0',
            result: {
                chainId: 84532,
                environment: 'testnet',
                name: 'Base Sepolia',
            },
        });
    });

    it('rejects unsupported chains', async () => {
        const app = createChainPolicyApp();

        const response = await app.request('http://localhost/v1/test/chains', {
            method: 'POST',
            headers: jsonHeaders(),
            body: JSON.stringify({
                id: 'chain_unsupported',
                jsonrpc: '2.0',
                method: 'knot_chainPolicyTest',
                params: {
                    chainId: 1,
                },
            }),
        });

        expect(response.status).toBe(400);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'chain_unsupported',
            jsonrpc: '2.0',
            error: {
                code: -32602,
                message: 'invalid_params:params.chainId',
                reason: 'invalid_params:params.chainId',
            },
        });
    });

    it('rejects unsupported entry points when present', async () => {
        const app = createRelayChainPolicyApp();

        const response = await app.request('http://localhost/v1/test/relay', {
            method: 'POST',
            headers: jsonHeaders(),
            body: JSON.stringify({
                id: 'chain_bad_entrypoint',
                jsonrpc: '2.0',
                method: 'knot_relaySubmit',
                params: {
                    chainId: 84532,
                    kind: 'single',
                    request: [
                        {
                            callData: '0x',
                            callGasLimit: '0x1',
                            maxFeePerGas: '0x0',
                            maxPriorityFeePerGas: '0x0',
                            nonce: '0x1',
                            preVerificationGas: '0x1',
                            sender: '0x1111111111111111111111111111111111111111',
                            signature: '0x',
                            verificationGasLimit: '0x1',
                        },
                        '0x0000000000000000000000000000000000000001',
                    ],
                },
            }),
        });

        expect(response.status).toBe(400);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'chain_bad_entrypoint',
            jsonrpc: '2.0',
            error: {
                code: -32602,
                message: 'invalid_params:params.request.1',
                reason: 'invalid_params:params.request.1',
            },
        });
    });
});

import { zValidator } from '@hono/zod-validator';
import { describe, expect, it } from 'bun:test';
import type { Context } from 'hono';
import { Hono } from 'hono';

import { chainPolicy } from '../src/middleware/chain-policy';
import { relaySubmitSchema, rpcHook } from '../src/schemas/rpc';
import type { AppBindings, BundlerClient, RpcFailure, RpcSuccess } from '../src/types';
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

function createRelayOperation(chainId: number, sender = '0x1111111111111111111111111111111111111111') {
    return {
        callData: '0x',
        callGasLimit: '0x1',
        chainId,
        maxFeePerGas: '0x0',
        maxPriorityFeePerGas: '0x0',
        nonce: '0x1',
        preVerificationGas: '0x1',
        sender,
        signature: '0x',
        strategy: 'immediate',
        verificationGasLimit: '0x1',
    };
}

function createRelayChainPolicyApp() {
    const app = new Hono<AppBindings>();
    const bundler = {} as BundlerClient;

    app.post(
        '/v1/test/relay',
        zValidator('json', relaySubmitSchema, rpcHook),
        chainPolicy({ bundler }),
        (c: Context<AppBindings>) => {
            const rpc = (
                c.req.valid as (target: 'json') => {
                    id: string | number | null;
                }
            )('json');
            const chain = c.get('chain');
            const [firstChain] = Object.values(chain);

            return c.json(
                rpcResult(rpc.id, {
                    chainId: firstChain?.config.id,
                    environment: firstChain?.config.environment,
                    name: firstChain?.config.name,
                    ok: true,
                }),
            );
        },
    );

    return app;
}

describe('relay proxy chain config', () => {
    it('resolves supported mainnet and testnet chains', () => {
        expect(getChainConfig(8453).environment).toBe('mainnet');
        expect(getChainConfig(84532).environment).toBe('testnet');
    });

    it('filters supported chains by environment', () => {
        expect(getMainnetChains().every((chain) => chain.environment === 'mainnet')).toBe(true);
        expect(getTestnetChains().every((chain) => chain.environment === 'testnet')).toBe(true);

        expect(getSupportedChains('mainnet')).toHaveLength(getMainnetChains().length);
        expect(getSupportedChains('testnet')).toHaveLength(getTestnetChains().length);
        expect(getSupportedChains()).toHaveLength(getMainnetChains().length + getTestnetChains().length);
    });

    it('builds a json rpc url from chain id and api key', () => {
        expect(buildJsonRpcUrl(84532, 'secret')).toBe('https://edge.goldsky.com/standard/evm/84532?secret=secret');
    });

    it('builds a sponsored bundler url from chain id', () => {
        expect(buildBundlerUrl(84532)).toBe('https://api.gelato.cloud/rpc/84532?payment=sponsored');
    });
});

describe('relay proxy chain policy middleware', () => {
    it('attaches a supported chain to the request context', async () => {
        const app = createRelayChainPolicyApp();

        const response = await app.request('http://localhost/v1/test/relay', {
            method: 'POST',
            headers: jsonHeaders(),
            body: JSON.stringify({
                id: 'chain_supported',
                jsonrpc: '2.0',
                method: 'knot_relaySubmit',
                params: {
                    request: [[createRelayOperation(84532)], '0x0000000071727De22E5E9d8BAf0edAc6f37da032'],
                },
            }),
        });

        expect(response.status).toBe(200);
        expect(
            await readJson<RpcSuccess<{ chainId: number; environment: string; name: string; ok: boolean }>>(response),
        ).toEqual({
            id: 'chain_supported',
            jsonrpc: '2.0',
            result: {
                chainId: 84532,
                environment: 'testnet',
                name: 'Base Sepolia',
                ok: true,
            },
        });
    });

    it('rejects unsupported chains', async () => {
        const app = createRelayChainPolicyApp();

        const response = await app.request('http://localhost/v1/test/relay', {
            method: 'POST',
            headers: jsonHeaders(),
            body: JSON.stringify({
                id: 'chain_unsupported',
                jsonrpc: '2.0',
                method: 'knot_relaySubmit',
                params: {
                    request: [[createRelayOperation(1)], '0x0000000071727De22E5E9d8BAf0edAc6f37da032'],
                },
            }),
        });

        expect(response.status).toBe(400);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'chain_unsupported',
            jsonrpc: '2.0',
            error: {
                code: -32602,
                details: [
                    {
                        message: expect.any(String),
                        path: 'params.request.0.0.chainId',
                    },
                ],
                message: 'invalid_params:params.request.0.0.chainId',
                reason: 'invalid_params:params.request.0.0.chainId',
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
                    request: [[createRelayOperation(84532)], '0x0000000000000000000000000000000000000001'],
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

    it('rejects relay requests with duplicate operation chain IDs', async () => {
        const app = createRelayChainPolicyApp();

        const response = await app.request('http://localhost/v1/test/relay', {
            method: 'POST',
            headers: jsonHeaders(),
            body: JSON.stringify({
                id: 'chain_duplicate',
                jsonrpc: '2.0',
                method: 'knot_relaySubmit',
                params: {
                    fillId: '0x1234',
                    request: [
                        [
                            createRelayOperation(84532, '0x1111111111111111111111111111111111111111'),
                            {
                                ...createRelayOperation(84532, '0x1111111111111111111111111111111111111111'),
                                nonce: '0x2',
                                strategy: 'background',
                            },
                            {
                                ...createRelayOperation(421614, '0x1111111111111111111111111111111111111111'),
                                nonce: '0x3',
                                strategy: 'deferred',
                            },
                        ],
                        '0x0000000071727De22E5E9d8BAf0edAc6f37da032',
                    ],
                },
            }),
        });

        expect(response.status).toBe(400);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'chain_duplicate',
            jsonrpc: '2.0',
            error: {
                code: -32602,
                details: expect.arrayContaining([
                    {
                        message: 'Relay operations must target unique chain IDs.',
                        path: 'params.request.0',
                    },
                ]),
                message: 'invalid_params:params.request.0',
                reason: 'invalid_params:params.request.0',
            },
        });
    });
});

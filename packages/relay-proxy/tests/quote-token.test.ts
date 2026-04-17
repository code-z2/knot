import { zValidator } from '@hono/zod-validator';
import { describe, expect, it } from 'bun:test';
import { Hono } from 'hono';
import type { Address } from 'viem';
import type { RpcUserOperation } from 'viem/account-abstraction';

import { chainPolicy } from '../src/middleware/chain-policy';
import { quoteToken } from '../src/middleware/quote-token';
import { relaySubmitSchema, rpcHook } from '../src/schemas/rpc';
import type { AppBindings, BundlerClient, CreateAppOptions, RpcFailure } from '../src/types';
import { rpcResult } from '../src/utils';
import { jsonHeaders, readJson } from './helpers/http';

function createRelayOperation(chainId: number, strategy: 'immediate' | 'background' | 'deferred', nonce: string) {
    return {
        callData: '0x',
        callGasLimit: '0x1',
        chainId,
        maxFeePerGas: '0x0',
        maxPriorityFeePerGas: '0x0',
        nonce,
        preVerificationGas: '0x1',
        sender: '0x1111111111111111111111111111111111111111',
        signature: '0x',
        strategy,
        verificationGasLimit: '0x1',
    };
}

function createQuoteApp(client: BundlerClient) {
    const app = new Hono<AppBindings>();
    const options: CreateAppOptions = {
        bundler: client,
    };

    app.post(
        '/v1/test/quote',
        zValidator('json', relaySubmitSchema, rpcHook),
        chainPolicy(options),
        quoteToken(),
        (c) => {
            const rpc = c.req.valid('json');

            return c.json(
                rpcResult(rpc.id, {
                    quote: c.get('quotes'),
                }),
            );
        },
    );

    return app;
}

function createQuoteRequest(body: unknown) {
    return new Request('http://localhost/v1/test/quote', {
        body: JSON.stringify(body),
        headers: jsonHeaders(),
        method: 'POST',
    });
}

describe('relay proxy quote middleware', () => {
    it('quotes a single user operation', async () => {
        const requests: unknown[] = [];
        const app = createQuoteApp({
            getUserOperationQuote: async (userOperation: RpcUserOperation, entryPoint: Address) => {
                requests.push({ entryPoint, userOperation });
                return {
                    callGasLimit: '0x1',
                    fee: '0x2',
                    gas: '0x3',
                    l1Fee: '0x0',
                    preVerificationGas: '0x4',
                    verificationGasLimit: '0x5',
                };
            },
        } as never);

        const response = await app.fetch(
            createQuoteRequest({
                id: 'quote_single',
                jsonrpc: '2.0',
                method: 'knot_relaySubmit',
                params: {
                    request: [
                        [createRelayOperation(84532, 'immediate', '0x1')],
                        '0x0000000071727De22E5E9d8BAf0edAc6f37da032',
                    ],
                },
            }),
            {
                BUNDLER_API_KEY: 'api-key',
            } as never,
        );

        expect(response.status).toBe(200);
        expect(requests).toHaveLength(1);
        expect(await readJson<unknown>(response)).toEqual({
            id: 'quote_single',
            jsonrpc: '2.0',
            result: {
                quote: {
                    84532: {
                        callGasLimit: '0x1',
                        fee: '0x2',
                        gas: '0x3',
                        l1Fee: '0x0',
                        preVerificationGas: '0x4',
                        verificationGasLimit: '0x5',
                    },
                },
            },
        });
    });

    it('quotes immediate and background operations but skips deferred', async () => {
        const requests: unknown[] = [];
        const app = createQuoteApp({
            getUserOperationQuote: async (userOperation: RpcUserOperation, entryPoint: Address) => {
                requests.push({ entryPoint, userOperation });
                return {
                    callGasLimit: '0x1',
                    fee: '0x2',
                    gas: '0x3',
                    l1Fee: '0x0',
                    preVerificationGas: '0x4',
                    verificationGasLimit: '0x5',
                };
            },
        } as never);

        const response = await app.fetch(
            createQuoteRequest({
                id: 'quote_plan',
                jsonrpc: '2.0',
                method: 'knot_relaySubmit',
                params: {
                    fillId: '0x1234',
                    request: [
                        [
                            createRelayOperation(84532, 'immediate', '0x1'),
                            createRelayOperation(421614, 'background', '0x2'),
                            createRelayOperation(11155111, 'deferred', '0x3'),
                        ],
                        '0x0000000071727De22E5E9d8BAf0edAc6f37da032',
                    ],
                },
            }),
            {
                BUNDLER_API_KEY: 'api-key',
            } as never,
        );

        expect(response.status).toBe(200);
        expect(requests).toHaveLength(2);
        expect(await readJson<unknown>(response)).toEqual({
            id: 'quote_plan',
            jsonrpc: '2.0',
            result: {
                quote: {
                    421614: {
                        callGasLimit: '0x1',
                        fee: '0x2',
                        gas: '0x3',
                        l1Fee: '0x0',
                        preVerificationGas: '0x4',
                        verificationGasLimit: '0x5',
                    },
                    84532: {
                        callGasLimit: '0x1',
                        fee: '0x2',
                        gas: '0x3',
                        l1Fee: '0x0',
                        preVerificationGas: '0x4',
                        verificationGasLimit: '0x5',
                    },
                },
            },
        });
    });

    it('returns bundler_unavailable when the quote call fails', async () => {
        const app = createQuoteApp({
            async getUserOperationQuote() {
                throw new Error('no bundler');
            },
        } as never);

        const response = await app.fetch(
            createQuoteRequest({
                id: 'quote_fail',
                jsonrpc: '2.0',
                method: 'knot_relaySubmit',
                params: {
                    request: [
                        [createRelayOperation(84532, 'immediate', '0x1')],
                        '0x0000000071727De22E5E9d8BAf0edAc6f37da032',
                    ],
                },
            }),
            {
                BUNDLER_API_KEY: 'api-key',
            } as never,
        );

        expect(response.status).toBe(500);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'quote_fail',
            jsonrpc: '2.0',
            error: {
                code: -32000,
                message: 'bundler_not_configured',
                reason: 'bundler_not_configured',
            },
        });
    });
});

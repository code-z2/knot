import { describe, expect, it } from 'bun:test';

import { createIntentExecutionStore } from '../src/stores/intent-execution';
import type { Address, Hex } from 'viem';
import type { RpcUserOperation } from 'viem/account-abstraction';
import type { RpcFailure, RpcSuccess, SendUserOperationBatchResult } from '../src/types';
import { uint } from '../src/utils';
import { createTestApp } from './helpers/app';
import { registerUser } from './helpers/auth-flow';
import { jsonHeaders, readJson } from './helpers/http';

function createMockKV() {
    const records = new Map<string, string>();

    return {
        async delete(key: string) {
            records.delete(key);
        },
        async get(key: string) {
            return records.get(key) ?? null;
        },
        async list() {
            return {
                cursor: '',
                keys: [...records.keys()].map((name) => ({ name })),
                list_complete: true,
            };
        },
        async put(key: string, value: string) {
            records.set(key, value);
        },
        records,
    };
}

function createQueue<T>() {
    const sent: T[] = [];

    return {
        async send(message: T) {
            sent.push(message);
        },
        sent,
    };
}

function createRelayEnv(kv: ReturnType<typeof createMockKV>, queue: ReturnType<typeof createQueue<string>>) {
    return {
        ANOMALY_QUEUE: createQueue<unknown>() as never,
        AUTH_DB: {} as never,
        AUTH_KV: {} as never,
        BUNDLER_API_KEY: 'bundler-api-key',
        GAS_USAGE_KV: createMockKV() as never,
        JSON_RPC_API_KEY: 'rpc-api-key',
        KNOT_APPLE_BUNDLE_ID: 'app.knot.ios',
        KNOT_APPLE_TEAM_ID: 'TEAM123456',
        KNOT_APP_ATTEST_ALLOW_DEVELOPMENT: 'true',
        KNOT_RP_ID: 'knot.fi',
        KNOT_RP_NAME: 'Knot',
        KNOT_RP_ORIGIN: 'https://knot.fi',
        PINATA_GATEWAY_BASE_URL: 'https://gateway.pinata.cloud',
        PINATA_IMAGE_GROUP_ID: 'group',
        PINATA_JWT: 'jwt',
        RELAY_KV: kv as never,
        RELAY_QUEUE: queue as never,
    } as never;
}

function createRelayRequest(body: unknown, accessToken: string, appAttestKeyId: string) {
    return new Request('http://localhost/v1/relay/submit', {
        body: JSON.stringify(body),
        headers: {
            authorization: `Bearer ${accessToken}`,
            'x-knot-app-attest-assertion': 'assertion:relay',
            'x-knot-app-attest-key-id': appAttestKeyId,
            'x-knot-nonce': `nonce-${body instanceof Object && 'id' in body ? String(body.id) : 'relay'}`,
            'x-knot-timestamp': String(Date.now()),
            ...jsonHeaders(),
        },
        method: 'POST',
    });
}

function createUserOperation(sender: string, nonce: Hex): RpcUserOperation {
    return {
        callData: '0x',
        callGasLimit: '0x1',
        maxFeePerGas: '0x0',
        maxPriorityFeePerGas: '0x0',
        nonce,
        preVerificationGas: '0x1',
        sender: sender as Address,
        signature: '0x',
        verificationGasLimit: '0x1',
    };
}

function createRelayOperation(
    sender: string,
    nonce: Hex,
    chainId: number,
    strategy: 'immediate' | 'background' | 'deferred',
) {
    return {
        ...createUserOperation(sender, nonce),
        chainId,
        strategy,
    };
}

function createRelayGasClient(userId: string) {
    return {
        async admitExposure() {
            return { pendingExposureUsdc: '0x2' };
        },
        async decrementPendingExposure() {
            return { pendingExposureUsdc: '0x0' };
        },
        async incrementOutstandingDebt() {
            return { outstandingDebtUsdc: '0x2' };
        },
        async ctx() {
            return {
                balanceUsdc: uint('0xffff'),
                gasProfile: {
                    minimumAllowedUsdc: uint.zero,
                    overdraftEligible: false,
                    overdraftEnabled: false,
                    overdraftLocked: false,
                    overdraftOutstandingUsdc: uint.zero,
                    outstandingDebtUsdc: uint.zero,
                    updatedAt: 0,
                    userId,
                },
                pendingExposureUsdc: uint.zero,
                provider: { kind: 'self' },
            };
        },
    } as never;
}

describe('relay proxy relay submit route', () => {
    it('submits a single user operation inline', async () => {
        const kv = createMockKV();
        const queue = createQueue<string>();
        const calls: Array<{ type: string; value: unknown[] }> = [];
        const userId = '0x1111111111111111111111111111111111111111';
        const immediateReceipt = {
            actualGasCost: '0x1',
            actualGasUsed: '0x2',
            entryPoint: '0x0000000071727De22E5E9d8BAf0edAc6f37da032',
            logs: [],
            nonce: '0x1',
            paymaster: null,
            reason: null,
            receipt: {
                blockHash: '0xblock',
                blockNumber: '0x1',
                contractAddress: null,
                cumulativeGasUsed: '0x1',
                effectiveGasPrice: '0x1',
                from: userId,
                gasUsed: '0x1',
                logs: [],
                logsBloom: `0x${'0'.repeat(512)}`,
                status: '0x1',
                to: userId,
                transactionHash: '0xtx',
                transactionIndex: '0x0',
                type: '0x2',
            },
            sender: userId,
            success: true,
            userOpHash: '0xsinglehash',
        };
        const { app } = createTestApp({
            bundler: {
                async getUserOperationQuote(userOperation: RpcUserOperation, entryPoint: Address) {
                    calls.push({
                        type: 'quote',
                        value: [userOperation, entryPoint],
                    });

                    return {
                        callGasLimit: '0x1',
                        fee: '0x2',
                        gas: '0x3',
                        l1Fee: '0x0',
                        preVerificationGas: '0x4',
                        verificationGasLimit: '0x5',
                    };
                },
                async sendUserOperation(userOperation: RpcUserOperation, entryPoint: Address) {
                    calls.push({
                        type: 'send',
                        value: [userOperation, entryPoint],
                    });

                    return '0xsinglehash';
                },
                async sendUserOperationBatch() {
                    throw new Error('not_used');
                },
                async sendUserOperationSync(userOperation: RpcUserOperation, entryPoint: Address) {
                    calls.push({
                        type: 'sync',
                        value: [userOperation, entryPoint],
                    });

                    return immediateReceipt as never;
                },
            } as never,
            gasClient: createRelayGasClient(userId),
        });

        const { verifyBody } = await registerUser(app, {
            appAttestKeyId: 'attest-key-relay-single',
            credentialId: 'credential-relay-single',
            userId,
        });

        const response = await app.fetch(
            createRelayRequest(
                {
                    id: 'relay_single',
                    jsonrpc: '2.0',
                    method: 'knot_relaySubmit',
                    params: {
                        request: [
                            [createRelayOperation(userId, '0x1', 84532, 'immediate')],
                            '0x0000000071727De22E5E9d8BAf0edAc6f37da032',
                        ],
                    },
                },
                verifyBody.result.accessToken,
                verifyBody.result.appAttestKeyId,
            ),
            createRelayEnv(kv, queue),
        );

        expect(response.status).toBe(200);
        expect(await readJson<RpcSuccess<{ immediate: typeof immediateReceipt }>>(response)).toEqual({
            id: 'relay_single',
            jsonrpc: '2.0',
            result: {
                immediate: immediateReceipt,
            },
        });
        expect(calls.map((call) => call.type)).toEqual(['quote', 'sync']);
        expect(queue.sent).toEqual([]);
        expect([...kv.records.keys()]).toEqual([]);
    });

    it('submits a relay plan, stores deferred intent execution, and queues its fillId', async () => {
        const kv = createMockKV();
        const queue = createQueue<string>();
        const userId = '0x2222222222222222222222222222222222222222';
        const calls: string[] = [];
        const immediateReceipt = {
            actualGasCost: '0x1',
            actualGasUsed: '0x2',
            entryPoint: '0x0000000071727De22E5E9d8BAf0edAc6f37da032',
            logs: [],
            nonce: '0x1',
            paymaster: null,
            reason: null,
            receipt: {
                blockHash: '0xblock',
                blockNumber: '0x1',
                contractAddress: null,
                cumulativeGasUsed: '0x1',
                effectiveGasPrice: '0x1',
                from: userId,
                gasUsed: '0x1',
                logs: [],
                logsBloom: `0x${'0'.repeat(512)}`,
                status: '0x1',
                to: userId,
                transactionHash: '0xtx',
                transactionIndex: '0x0',
                type: '0x2',
            },
            sender: userId,
            success: true,
            userOpHash: '0ximmediatehash',
        };
        const { app } = createTestApp({
            bundler: {
                async getUserOperationQuote() {
                    return {
                        callGasLimit: '0x1',
                        fee: '0x2',
                        gas: '0x3',
                        l1Fee: '0x0',
                        preVerificationGas: '0x4',
                        verificationGasLimit: '0x5',
                    };
                },
                async sendUserOperation() {
                    calls.push('send');
                    return '0xbackground1';
                },
                async sendUserOperationBatch() {
                    throw new Error('not_used');
                },
                async sendUserOperationSync() {
                    calls.push('sync');
                    return immediateReceipt as never;
                },
            } as never,
            gasClient: createRelayGasClient(userId),
        });

        const { verifyBody } = await registerUser(app, {
            appAttestKeyId: 'attest-key-relay-plan',
            credentialId: 'credential-relay-plan',
            userId,
        });

        const response = await app.fetch(
            createRelayRequest(
                {
                    id: 'relay_plan',
                    jsonrpc: '2.0',
                    method: 'knot_relaySubmit',
                    params: {
                        fillId: '0x1234',
                        request: [
                            [
                                createRelayOperation(userId, '0x1', 84532, 'immediate'),
                                createRelayOperation(userId, '0x2', 421614, 'background'),
                                createRelayOperation(userId, '0x3', 11155111, 'deferred'),
                            ],
                            '0x0000000071727De22E5E9d8BAf0edAc6f37da032',
                        ],
                    },
                },
                verifyBody.result.accessToken,
                verifyBody.result.appAttestKeyId,
            ),
            createRelayEnv(kv, queue),
        );

        expect(response.status).toBe(200);
        expect(
            await readJson<
                RpcSuccess<{
                    background: readonly SendUserOperationBatchResult[];
                    deferred: { fillId: string; queued: boolean };
                    immediate: typeof immediateReceipt;
                }>
            >(response),
        ).toEqual({
            id: 'relay_plan',
            jsonrpc: '2.0',
            result: {
                background: [
                    {
                        chainId: 421614,
                        hash: '0xbackground1',
                        ok: true,
                    },
                ],
                deferred: {
                    fillId: '0x1234',
                    queued: true,
                },
                immediate: immediateReceipt,
            },
        });
        expect(calls).toEqual(['sync', 'send']);
        expect(queue.sent).toEqual(['0x1234']);

        const store = createIntentExecutionStore({
            RELAY_KV: kv as unknown as KVNamespace,
        });
        const record = await store.get('0x1234');

        expect(record).not.toBeNull();
        expect(record?.chainId).toBe(11155111);
        expect(record?.fillId).toBe('0x1234');
        expect(record?.userOperation.sender).toBe(userId);
    });

    it('rejects relay requests whose sender does not match the authenticated user', async () => {
        const kv = createMockKV();
        const queue = createQueue<string>();
        const userId = '0x3333333333333333333333333333333333333333';
        const { app } = createTestApp({
            bundler: {
                async getUserOperationQuote() {
                    return {
                        callGasLimit: '0x1',
                        fee: '0x2',
                        gas: '0x3',
                        l1Fee: '0x0',
                        preVerificationGas: '0x4',
                        verificationGasLimit: '0x5',
                    };
                },
                async sendUserOperation() {
                    throw new Error('should_not_send');
                },
                async sendUserOperationBatch() {
                    throw new Error('should_not_send');
                },
                async sendUserOperationSync() {
                    throw new Error('should_not_send');
                },
            } as never,
            gasClient: createRelayGasClient(userId),
        });

        const { verifyBody } = await registerUser(app, {
            appAttestKeyId: 'attest-key-relay-mismatch',
            credentialId: 'credential-relay-mismatch',
            userId,
        });

        const response = await app.fetch(
            createRelayRequest(
                {
                    id: 'relay_sender_mismatch',
                    jsonrpc: '2.0',
                    method: 'knot_relaySubmit',
                    params: {
                        request: [
                            [
                                createRelayOperation(
                                    '0x4444444444444444444444444444444444444444',
                                    '0x1',
                                    84532,
                                    'immediate',
                                ),
                            ],
                            '0x0000000071727De22E5E9d8BAf0edAc6f37da032',
                        ],
                    },
                },
                verifyBody.result.accessToken,
                verifyBody.result.appAttestKeyId,
            ),
            createRelayEnv(kv, queue),
        );

        expect(response.status).toBe(400);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'relay_sender_mismatch',
            jsonrpc: '2.0',
            error: {
                code: -32602,
                message: 'invalid_params:sender mismatch',
                reason: 'invalid_params:sender mismatch',
            },
        });
    });
});

import { describe, expect, it } from 'bun:test';

import {
    INTENT_EXECUTION_ANOMALY_RETRY_AFTER_MS,
    INTENT_EXECUTION_KEY_PREFIX,
    INTENT_EXECUTION_MAX_ATTEMPTS,
    INTENT_EXECUTION_RETRY_AFTER_MS,
    INTENT_EXECUTION_TTL_WARNING_MS,
} from '../src/constants';
import { createIntentExecutionStore } from '../src/stores/intent-execution';
import { consumeIntentExecutionBatch, sweepIntentExecutions } from '../src/workers/intent-execution';
import type {
    AnomalyQueueMessage,
    CloudflareBindings,
    IntentExecutionQueueMessage,
    IntentExecutionRecord,
} from '../src/types';

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

function createBatch(messages: readonly IntentExecutionQueueMessage[]) {
    const state = messages.map((body) => ({
        ackCount: 0,
        body,
        retryCount: 0,
    }));

    return {
        batch: {
            messages: state.map((message) => ({
                ack() {
                    message.ackCount += 1;
                },
                body: message.body,
                retry() {
                    message.retryCount += 1;
                },
            })),
            queue: 'intent-execution-queue',
        } as unknown as MessageBatch<IntentExecutionQueueMessage>,
        state,
    };
}

function createRecord(overrides: Partial<IntentExecutionRecord> = {}): IntentExecutionRecord {
    return {
        attempts: 0,
        chainId: 84532,
        createdAt: '2026-04-01T10:00:00.000Z',
        entryPoint: '0x0000000071727De22E5E9d8BAf0edAc6f37da032',
        expiresAt: '2026-05-01T10:00:00.000Z',
        fillId: '0x1234',
        userOperation: {
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
        ...overrides,
    };
}

describe('relay proxy intent execution store', () => {
    it('stores and loads intent execution records under the canonical key', async () => {
        const kv = createMockKV();
        const store = createIntentExecutionStore({
            RELAY_KV: kv as unknown as KVNamespace,
        });
        const record = createRecord();

        await store.put(record);

        expect(await store.get(record.fillId)).toEqual(record);
        expect([...kv.records.keys()]).toEqual([`${INTENT_EXECUTION_KEY_PREFIX}${record.fillId}`]);
    });
});

describe('relay proxy intent execution worker', () => {
    it('submits intent execution records and deletes them on success', async () => {
        const kv = createMockKV();
        const store = createIntentExecutionStore({
            RELAY_KV: kv as unknown as KVNamespace,
        });
        const record = createRecord();
        await store.put(record);

        const calls: unknown[] = [];
        const { batch, state } = createBatch([record.fillId]);

        await consumeIntentExecutionBatch(
            batch,
            {
                BUNDLER_API_KEY: 'api-key' as never,
                JSON_RPC_API_KEY: 'rpc-key' as never,
                RELAY_KV: kv as unknown as KVNamespace,
            } as unknown as CloudflareBindings,
            (_config) =>
                ({
                    async sendUserOperation(userOperation: unknown, entryPoint: unknown) {
                        calls.push({
                            method: 'eth_sendUserOperation',
                            params: [userOperation, entryPoint],
                        });
                        return '0xhash';
                    },
                }) as never,
        );

        expect(state[0].ackCount).toBe(1);
        expect(state[0].retryCount).toBe(0);
        expect(calls).toEqual([
            {
                method: 'eth_sendUserOperation',
                params: [record.userOperation, record.entryPoint],
            },
        ]);
        expect(await store.get(record.fillId)).toBeNull();
    });

    it('retries when intent execution submission fails', async () => {
        const kv = createMockKV();
        const store = createIntentExecutionStore({
            RELAY_KV: kv as unknown as KVNamespace,
        });
        const record = createRecord();
        await store.put(record);

        const { batch, state } = createBatch([record.fillId]);

        await consumeIntentExecutionBatch(
            batch,
            {
                BUNDLER_API_KEY: 'api-key' as never,
                JSON_RPC_API_KEY: 'rpc-key' as never,
                RELAY_KV: kv as unknown as KVNamespace,
            } as unknown as CloudflareBindings,
            () => {
                throw new Error('send failed');
            },
        );

        expect(state[0].ackCount).toBe(0);
        expect(state[0].retryCount).toBe(1);
        expect(await store.get(record.fillId)).toEqual(record);
    });
});

describe('relay proxy intent execution cron', () => {
    it('enqueues retryable intent executions and increments the queued attempt state', async () => {
        const kv = createMockKV();
        const queue = createQueue<IntentExecutionQueueMessage>();
        const anomalyQueue = createQueue<AnomalyQueueMessage>();
        const store = createIntentExecutionStore({
            RELAY_KV: kv as unknown as KVNamespace,
        });
        const now = Date.parse('2026-04-01T12:00:00.000Z');
        const record = createRecord({
            createdAt: '2026-04-01T10:00:00.000Z',
            expiresAt: '2026-05-01T10:00:00.000Z',
        });
        await store.put(record);

        await sweepIntentExecutions(
            {
                ANOMALY_QUEUE: anomalyQueue as unknown as Queue<AnomalyQueueMessage>,
                RELAY_KV: kv as unknown as KVNamespace,
                RELAY_QUEUE: queue as unknown as Queue<IntentExecutionQueueMessage>,
            },
            now,
        );

        expect(queue.sent).toEqual([record.fillId]);
        expect(anomalyQueue.sent).toEqual([]);

        const updated = await store.get(record.fillId);
        expect(updated?.attempts).toBe(1);
        expect(updated?.lastQueuedAt).toBe('2026-04-01T12:00:00.000Z');
    });

    it('skips records that were queued too recently', async () => {
        const kv = createMockKV();
        const queue = createQueue<IntentExecutionQueueMessage>();
        const anomalyQueue = createQueue<AnomalyQueueMessage>();
        const store = createIntentExecutionStore({
            RELAY_KV: kv as unknown as KVNamespace,
        });
        const now = Date.parse('2026-04-01T12:00:00.000Z');
        const record = createRecord({
            attempts: 1,
            lastQueuedAt: new Date(now - INTENT_EXECUTION_RETRY_AFTER_MS + 60_000).toISOString(),
        });
        await store.put(record);

        await sweepIntentExecutions(
            {
                ANOMALY_QUEUE: anomalyQueue as unknown as Queue<AnomalyQueueMessage>,
                RELAY_KV: kv as unknown as KVNamespace,
                RELAY_QUEUE: queue as unknown as Queue<IntentExecutionQueueMessage>,
            },
            now,
        );

        expect(queue.sent).toEqual([]);
    });

    it('sends an anomaly and queues retryable records when the record is near expiry', async () => {
        const kv = createMockKV();
        const queue = createQueue<IntentExecutionQueueMessage>();
        const anomalyQueue = createQueue<AnomalyQueueMessage>();
        const store = createIntentExecutionStore({
            RELAY_KV: kv as unknown as KVNamespace,
        });
        const now = Date.parse('2026-04-01T12:00:00.000Z');
        const record = createRecord({
            expiresAt: new Date(now + INTENT_EXECUTION_TTL_WARNING_MS - 1).toISOString(),
        });
        await store.put(record);

        await sweepIntentExecutions(
            {
                ANOMALY_QUEUE: anomalyQueue as unknown as Queue<AnomalyQueueMessage>,
                RELAY_KV: kv as unknown as KVNamespace,
                RELAY_QUEUE: queue as unknown as Queue<IntentExecutionQueueMessage>,
            },
            now,
        );

        expect(queue.sent).toEqual([record.fillId]);
        expect(anomalyQueue.sent[0]?.type).toBe('anomaly_intent_execution_ttl_expiring');
        const updated = await store.get(record.fillId);
        expect(updated?.attempts).toBe(1);
        expect(updated?.lastAnomalyAt).toBe('2026-04-01T12:00:00.000Z');
        expect(updated?.lastQueuedAt).toBe('2026-04-01T12:00:00.000Z');
    });

    it('sends an anomaly after the retry budget is exhausted', async () => {
        const kv = createMockKV();
        const queue = createQueue<IntentExecutionQueueMessage>();
        const anomalyQueue = createQueue<AnomalyQueueMessage>();
        const store = createIntentExecutionStore({
            RELAY_KV: kv as unknown as KVNamespace,
        });
        const record = createRecord({
            attempts: INTENT_EXECUTION_MAX_ATTEMPTS,
        });
        await store.put(record);

        await sweepIntentExecutions(
            {
                ANOMALY_QUEUE: anomalyQueue as unknown as Queue<AnomalyQueueMessage>,
                RELAY_KV: kv as unknown as KVNamespace,
                RELAY_QUEUE: queue as unknown as Queue<IntentExecutionQueueMessage>,
            },
            Date.parse('2026-04-01T12:00:00.000Z'),
        );

        expect(queue.sent).toEqual([]);
        expect(anomalyQueue.sent[0]?.type).toBe('anomaly_intent_execution_retry_exhausted');
    });

    it('queues without resending an anomaly before the cooldown elapses', async () => {
        const kv = createMockKV();
        const queue = createQueue<IntentExecutionQueueMessage>();
        const anomalyQueue = createQueue<AnomalyQueueMessage>();
        const store = createIntentExecutionStore({
            RELAY_KV: kv as unknown as KVNamespace,
        });
        const now = Date.parse('2026-04-01T12:00:00.000Z');
        const record = createRecord({
            expiresAt: new Date(now + INTENT_EXECUTION_TTL_WARNING_MS - 1).toISOString(),
            lastAnomalyAt: new Date(now - INTENT_EXECUTION_ANOMALY_RETRY_AFTER_MS + 60_000).toISOString(),
        });
        await store.put(record);

        await sweepIntentExecutions(
            {
                ANOMALY_QUEUE: anomalyQueue as unknown as Queue<AnomalyQueueMessage>,
                RELAY_KV: kv as unknown as KVNamespace,
                RELAY_QUEUE: queue as unknown as Queue<IntentExecutionQueueMessage>,
            },
            now,
        );

        expect(queue.sent).toEqual([record.fillId]);
        expect(anomalyQueue.sent).toEqual([]);
        const updated = await store.get(record.fillId);
        expect(updated?.lastAnomalyAt).toBe(record.lastAnomalyAt);
        expect(updated?.lastQueuedAt).toBe('2026-04-01T12:00:00.000Z');
    });

    it('resends an anomaly after the cooldown elapses', async () => {
        const kv = createMockKV();
        const queue = createQueue<IntentExecutionQueueMessage>();
        const anomalyQueue = createQueue<AnomalyQueueMessage>();
        const store = createIntentExecutionStore({
            RELAY_KV: kv as unknown as KVNamespace,
        });
        const now = Date.parse('2026-04-01T12:00:00.000Z');
        const record = createRecord({
            expiresAt: new Date(now + INTENT_EXECUTION_TTL_WARNING_MS - 1).toISOString(),
            lastAnomalyAt: new Date(now - INTENT_EXECUTION_ANOMALY_RETRY_AFTER_MS).toISOString(),
        });
        await store.put(record);

        await sweepIntentExecutions(
            {
                ANOMALY_QUEUE: anomalyQueue as unknown as Queue<AnomalyQueueMessage>,
                RELAY_KV: kv as unknown as KVNamespace,
                RELAY_QUEUE: queue as unknown as Queue<IntentExecutionQueueMessage>,
            },
            now,
        );

        expect(queue.sent).toEqual([record.fillId]);
        expect(anomalyQueue.sent[0]?.type).toBe('anomaly_intent_execution_ttl_expiring');
        const updated = await store.get(record.fillId);
        expect(updated?.lastAnomalyAt).toBe('2026-04-01T12:00:00.000Z');
        expect(updated?.lastQueuedAt).toBe('2026-04-01T12:00:00.000Z');
    });
});

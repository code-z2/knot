import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';

import { sweepDeferredIntents } from '../workers/cron.worker';
import {
    createMockEnv,
    createMockKV,
    createMockQueue,
    type MockQueue,
} from '../../__tests__/mocks';
import { STUCK_THRESHOLD_MS, DEFERRED_TTL_WARNING_DAYS } from '../../shared/constants';
import type { Env } from '../../shared/types';
import type { AlertQueueMessage, DeferredRelayKVPayload, RelayQueueMessage } from '../types';

/**
 * Note: We mock globalThis.fetch to intercept the Alchemy RPC call made by
 * createChainClient → PublicClient.getLogs. This avoids needing vi.mock
 * (not supported in bun test) while still testing the full sweep flow.
 *
 * The topic must match keccak256("FillReady(bytes32,uint256,uint256)") because
 * viem filters returned logs against the event signature client-side.
 * The fillId topic must also match the payload's fillId (now filtered via args).
 */
const FILL_READY_TOPIC = '0x8c36863416e0816e242aad63de79f7f11d536787f63ccd2870cfbf324e459e5a';
/** Non-indexed ABI-encoded (totalReceived=1000000, sumOutput=500000). */
const MOCK_EVENT_DATA =
    '0x00000000000000000000000000000000000000000000000000000000000f4240000000000000000000000000000000000000000000000000000000000007a120';

/** Builds a JSON-RPC response with a FillReady log whose indexed fillId matches the payload. */
function mockRpcLogsResponse(fillId: string): string {
    return JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        result: [
            {
                topics: [FILL_READY_TOPIC, fillId],
                data: MOCK_EVENT_DATA,
                blockNumber: '0x1',
            },
        ],
    });
}

/** Realistic bytes32 fill IDs (keccak256 hashes in production). */
const MOCK_FILL_ID_A = '0xaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd';
const MOCK_FILL_ID_B = '0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef';

function makePayload(overrides: Partial<DeferredRelayKVPayload> = {}): DeferredRelayKVPayload {
    return {
        account: '0x9999999999999999999999999999999999999999',
        fillId: MOCK_FILL_ID_A,
        supportMode: 'testnet',
        chainId: 11155111,
        request: {
            from: '0x9999999999999999999999999999999999999999' as `0x${string}`,
            to: '0x1111111111111111111111111111111111111111' as `0x${string}`,
            data: '0xdeadbeef' as `0x${string}`,
        },
        createdAt: new Date().toISOString(),
        ...overrides,
    };
}

function kvKey(supportMode: string, fillId: string): string {
    return `deferred-relay:${supportMode}:${fillId}`;
}

describe('sweepDeferredIntents', () => {
    let env: Env;
    let relayQueue: MockQueue;
    let alertsQueue: MockQueue;

    beforeEach(() => {
        vi.restoreAllMocks();
        relayQueue = createMockQueue() as unknown as MockQueue;
        alertsQueue = createMockQueue() as unknown as MockQueue;
        env = createMockEnv({
            DEFERRED_RELAY_KV: createMockKV(),
            RELAY_BATCH_QUEUE: relayQueue as unknown as Queue,
            ALERTS_QUEUE: alertsQueue as unknown as Queue,
            ALCHEMY_NODE_API_KEY: 'test-key',
        });
    });

    afterEach(() => {
        vi.restoreAllMocks();
    });

    it('does nothing when KV is empty', async () => {
        await sweepDeferredIntents(env);
        expect(relayQueue.sent).toHaveLength(0);
        expect(alertsQueue.sent).toHaveLength(0);
    });

    it('skips intents that already have a gelatoId', async () => {
        const key = kvKey('testnet', MOCK_FILL_ID_A);
        const payload = makePayload({
            gelatoId: 'gelato-123',
            createdAt: new Date(Date.now() - STUCK_THRESHOLD_MS - 1000).toISOString(),
        });

        await env.DEFERRED_RELAY_KV.put(key, JSON.stringify(payload));

        await sweepDeferredIntents(env);

        expect(relayQueue.sent).toHaveLength(0);
    });

    it('skips intents younger than the stuck threshold', async () => {
        const key = kvKey('testnet', MOCK_FILL_ID_A);
        const payload = makePayload({ createdAt: new Date().toISOString() });

        await env.DEFERRED_RELAY_KV.put(key, JSON.stringify(payload));

        await sweepDeferredIntents(env);

        expect(relayQueue.sent).toHaveLength(0);
    });

    it('recovers stuck intents when on-chain check passes', async () => {
        const accumulator = '0x1111111111111111111111111111111111111111';
        const fillId = MOCK_FILL_ID_A;
        const key = kvKey('testnet', fillId);
        const payload = makePayload({
            fillId,
            createdAt: new Date(Date.now() - STUCK_THRESHOLD_MS - 60_000).toISOString(),
        });

        // Mock the RPC call to return a FillReady log matching this fillId
        vi.spyOn(globalThis, 'fetch').mockResolvedValue(
            new Response(mockRpcLogsResponse(fillId), {
                status: 200,
                headers: { 'Content-Type': 'application/json' },
            }),
        );

        await env.DEFERRED_RELAY_KV.put(key, JSON.stringify(payload));

        await sweepDeferredIntents(env);

        expect(relayQueue.sent).toHaveLength(1);
        expect((relayQueue.sent[0] as RelayQueueMessage).type).toBe('execute_intent');
        expect((relayQueue.sent[0] as RelayQueueMessage).accumulatorAddress).toBe(accumulator);

        // Should also send a sweeper recovery alert
        const recoveryAlerts = alertsQueue.sent.filter(
            (m: unknown) => (m as AlertQueueMessage).type === 'anomaly_sweeper_recovery',
        );
        expect(recoveryAlerts).toHaveLength(1);
    });

    it('uses payload.request.to as accumulator address', async () => {
        const accumulator = '0xabcdef1234567890abcdef1234567890abcdef12';
        const fillId = MOCK_FILL_ID_B;
        const key = kvKey('mainnet', fillId);
        const payload = makePayload({
            supportMode: 'mainnet',
            fillId,
            request: {
                from: '0x9999999999999999999999999999999999999999' as `0x${string}`,
                to: accumulator as `0x${string}`,
                data: '0xdeadbeef' as `0x${string}`,
            },
            createdAt: new Date(Date.now() - STUCK_THRESHOLD_MS - 60_000).toISOString(),
        });

        vi.spyOn(globalThis, 'fetch').mockResolvedValue(
            new Response(mockRpcLogsResponse(fillId), {
                status: 200,
                headers: { 'Content-Type': 'application/json' },
            }),
        );

        await env.DEFERRED_RELAY_KV.put(key, JSON.stringify(payload));

        await sweepDeferredIntents(env);

        const recovered = relayQueue.sent[0] as RelayQueueMessage;
        expect(recovered.accumulatorAddress).toBe(accumulator);
        expect(recovered.accumulatorAddress).not.toBe(fillId);
    });

    it('sends TTL warning for old undispatched intents', async () => {
        // No fetch mock needed — TTL check happens before on-chain verification
        const key = kvKey('testnet', MOCK_FILL_ID_A);
        const daysOld = DEFERRED_TTL_WARNING_DAYS + 1;
        const payload = makePayload({
            createdAt: new Date(Date.now() - daysOld * 24 * 60 * 60 * 1000).toISOString(),
        });

        await env.DEFERRED_RELAY_KV.put(key, JSON.stringify(payload));

        // Mock fetch to return empty logs (doesn't matter, TTL alert fires first)
        vi.spyOn(globalThis, 'fetch').mockResolvedValue(
            new Response(JSON.stringify({ jsonrpc: '2.0', id: 1, result: [] }), {
                status: 200,
                headers: { 'Content-Type': 'application/json' },
            }),
        );

        await sweepDeferredIntents(env);

        const ttlAlerts = alertsQueue.sent.filter(
            (m: unknown) => (m as AlertQueueMessage).type === 'anomaly_deferred_ttl_expiring',
        );
        expect(ttlAlerts.length).toBeGreaterThanOrEqual(1);
    });

    it('does not send TTL warning for dispatched intents', async () => {
        const key = kvKey('testnet', MOCK_FILL_ID_A);
        const daysOld = DEFERRED_TTL_WARNING_DAYS + 1;
        const payload = makePayload({
            gelatoId: 'already-dispatched',
            createdAt: new Date(Date.now() - daysOld * 24 * 60 * 60 * 1000).toISOString(),
        });

        await env.DEFERRED_RELAY_KV.put(key, JSON.stringify(payload));

        await sweepDeferredIntents(env);

        const ttlAlerts = alertsQueue.sent.filter(
            (m: unknown) => (m as AlertQueueMessage).type === 'anomaly_deferred_ttl_expiring',
        );
        expect(ttlAlerts).toHaveLength(0);
    });
});

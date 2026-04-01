import { afterEach, beforeEach, describe, expect, it } from 'bun:test';

import { consumeAnomalyBatch } from '../src/workers/anomaly';
import type { AnomalyQueueMessage } from '../src/types';

type TestMessage = {
    ackCount: number;
    body: AnomalyQueueMessage;
    retryCount: number;
};

function createBatch(messages: readonly AnomalyQueueMessage[]) {
    const state: TestMessage[] = messages.map((body) => ({
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
            queue: 'anomaly-queue',
        } as unknown as MessageBatch<AnomalyQueueMessage>,
        state,
    };
}

const anomaly: AnomalyQueueMessage = {
    body: 'Intent execution is close to expiry and will stop retrying.',
    createdAt: '2026-04-01T10:00:00.000Z',
    fillId: '0x1234',
    severity: 'warning',
    title: 'Intent execution nearing TTL',
    type: 'anomaly_intent_execution_ttl_expiring',
    userId: '0x1111111111111111111111111111111111111111',
};

describe('relay proxy anomaly queue worker', () => {
    const originalFetch = globalThis.fetch;

    beforeEach(() => {
        globalThis.fetch = originalFetch;
    });

    afterEach(() => {
        globalThis.fetch = originalFetch;
    });

    it('acks messages after successful Discord delivery', async () => {
        const calls: RequestInit[] = [];
        globalThis.fetch = (async (_input: RequestInfo | URL, init?: RequestInit) => {
            calls.push(init ?? {});
            return new Response('ok', { status: 200 });
        }) as unknown as typeof fetch;

        const { batch, state } = createBatch([anomaly]);

        await consumeAnomalyBatch(batch, {
            DISCORD_WEBHOOK_URL: 'https://discord.test/webhook',
        });

        expect(state[0].ackCount).toBe(1);
        expect(state[0].retryCount).toBe(0);
        expect(calls).toHaveLength(1);
    });

    it('acks messages when no delivery channel is configured', async () => {
        let called = false;
        globalThis.fetch = (async () => {
            called = true;
            return new Response('ok', { status: 200 });
        }) as unknown as typeof fetch;

        const { batch, state } = createBatch([anomaly]);

        await consumeAnomalyBatch(batch, {});

        expect(state[0].ackCount).toBe(1);
        expect(state[0].retryCount).toBe(0);
        expect(called).toBe(false);
    });

    it('retries messages when a configured delivery channel fails', async () => {
        globalThis.fetch = (async () => {
            return new Response('nope', { status: 500 });
        }) as unknown as typeof fetch;

        const { batch, state } = createBatch([anomaly]);

        await consumeAnomalyBatch(batch, {
            DISCORD_WEBHOOK_URL: 'https://discord.test/webhook',
        });

        expect(state[0].ackCount).toBe(0);
        expect(state[0].retryCount).toBe(1);
    });

    it('renders a generic Discord payload from the queue message', async () => {
        let content = '';
        globalThis.fetch = (async (_input: RequestInfo | URL, init?: RequestInit) => {
            const body = JSON.parse(String(init?.body));
            content = body.content;
            return new Response('ok', { status: 200 });
        }) as unknown as typeof fetch;

        const { batch } = createBatch([anomaly]);

        await consumeAnomalyBatch(batch, {
            DISCORD_WEBHOOK_URL: 'https://discord.test/webhook',
        });

        expect(content).toContain('Intent execution nearing TTL');
        expect(content).toContain('Intent execution is close to expiry');
        expect(content).toContain('0x1111111111111111111111111111111111111111');
        expect(content).toContain('0x1234');
        expect(content).toContain('anomaly_intent_execution_ttl_expiring');
    });
});

import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';

import { consumeAlertsBatch } from '../workers/alerts.worker';
import { createMockBatch, createMockEnv } from '../../__tests__/mocks';
import type { AlertQueueMessage } from '../types';

describe('consumeAlertsBatch', () => {
    const WEBHOOK_URL = 'https://discord.com/api/webhooks/test';

    beforeEach(() => {
        vi.restoreAllMocks();
    });

    afterEach(() => {
        vi.restoreAllMocks();
    });

    it('acks messages on successful dispatch', async () => {
        vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('ok', { status: 200 }));
        const env = createMockEnv({ DISCORD_ANOMALY_WEBHOOK_URL: WEBHOOK_URL });

        const batch = createMockBatch<AlertQueueMessage>([
            {
                type: 'anomaly_sweeper_recovery',
                accumulatorAddress: '0x1111111111111111111111111111111111111111',
                fillId: '0xaabb',
                supportMode: 'LIMITED_TESTNET',
                chainId: 11155111,
                recoveredAt: '2026-01-01T00:00:00Z',
            },
        ]);

        await consumeAlertsBatch(batch, env);

        expect(batch.messages[0].ack).toHaveBeenCalled();
        expect(batch.messages[0].retry).not.toHaveBeenCalled();
    });

    it('acks even when Discord returns error (allSettled swallows)', async () => {
        // dispatchAlert uses Promise.allSettled, so individual dispatcher failures
        // don't propagate. The message is still acked.
        vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('error', { status: 500 }));
        const env = createMockEnv({ DISCORD_ANOMALY_WEBHOOK_URL: WEBHOOK_URL });

        const batch = createMockBatch<AlertQueueMessage>([
            {
                type: 'anomaly_tracker_decrement_failed',
                accumulatorAddress: '0x1111111111111111111111111111111111111111',
                attempts: 3,
                error: 'DO unreachable',
            },
        ]);

        await consumeAlertsBatch(batch, env);

        // allSettled means the error is caught inside dispatchAlert, not propagated
        expect(batch.messages[0].ack).toHaveBeenCalled();
    });

    it('skips fetch when no webhook URL configured', async () => {
        const fetchSpy = vi.spyOn(globalThis, 'fetch');
        const envNoWebhook = createMockEnv();

        const batch = createMockBatch<AlertQueueMessage>([
            {
                type: 'anomaly_deferred_ttl_expiring',
                accumulatorAddress: '0x1111111111111111111111111111111111111111',
                fillId: '0xaabb',
                supportMode: 'LIMITED_MAINNET',
                chainId: 8453,
                ageDays: 8,
                ttlDays: 30,
            },
        ]);

        await consumeAlertsBatch(batch, envNoWebhook);

        expect(fetchSpy).not.toHaveBeenCalled();
        expect(batch.messages[0].ack).toHaveBeenCalled();
    });

    it('sends correct Discord payload for sweeper recovery', async () => {
        const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('ok'));
        const env = createMockEnv({ DISCORD_ANOMALY_WEBHOOK_URL: WEBHOOK_URL });

        const batch = createMockBatch<AlertQueueMessage>([
            {
                type: 'anomaly_sweeper_recovery',
                accumulatorAddress: '0xaaaa',
                fillId: '0xbbbb',
                supportMode: 'LIMITED_TESTNET',
                chainId: 11155111,
                recoveredAt: '2026-03-10T12:00:00Z',
            },
        ]);

        await consumeAlertsBatch(batch, env);

        expect(fetchSpy).toHaveBeenCalledOnce();
        const body = JSON.parse(fetchSpy.mock.calls[0][1]!.body as string);
        expect(body.content).toContain('Sweeper Recovery');
        expect(body.content).toContain('0xaaaa');
    });

    it('sends correct Discord payload for tracker decrement failure', async () => {
        const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('ok'));
        const env = createMockEnv({ DISCORD_ANOMALY_WEBHOOK_URL: WEBHOOK_URL });

        const batch = createMockBatch<AlertQueueMessage>([
            {
                type: 'anomaly_tracker_decrement_failed',
                accumulatorAddress: '0xcccc',
                attempts: 3,
                error: 'Network timeout',
            },
        ]);

        await consumeAlertsBatch(batch, env);

        const body = JSON.parse(fetchSpy.mock.calls[0][1]!.body as string);
        expect(body.content).toContain('Tracker Decrement Failed');
        expect(body.content).toContain('Network timeout');
    });

    it('sends correct Discord payload for TTL expiring', async () => {
        const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response('ok'));
        const env = createMockEnv({ DISCORD_ANOMALY_WEBHOOK_URL: WEBHOOK_URL });

        const batch = createMockBatch<AlertQueueMessage>([
            {
                type: 'anomaly_deferred_ttl_expiring',
                accumulatorAddress: '0xdddd',
                fillId: '0xeeee',
                supportMode: 'FULL_MAINNET',
                chainId: 1,
                ageDays: 25,
                ttlDays: 30,
            },
        ]);

        await consumeAlertsBatch(batch, env);

        const body = JSON.parse(fetchSpy.mock.calls[0][1]!.body as string);
        expect(body.content).toContain('Approaching TTL');
        expect(body.content).toContain('25 days / 30 day TTL');
    });
});

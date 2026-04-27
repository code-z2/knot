import { describe, expect, it } from 'bun:test';

import { consumeFaucetBatch } from '../src/workers/faucet';
import type { DOResponse, FaucetFundDOResult, FaucetQueueMessage } from '../src/types';

type TestMessage = {
    ackCount: number;
    body: FaucetQueueMessage;
    retryCount: number;
};

function createBatch(messages: readonly FaucetQueueMessage[]) {
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
            queue: 'faucet-queue',
        } as unknown as MessageBatch<FaucetQueueMessage>,
        state,
    };
}

function createDO(result: DOResponse<FaucetFundDOResult>) {
    return {
        idFromName(name: string) {
            return name as never;
        },
        get() {
            return {
                async fetch() {
                    return Response.json(result);
                },
            };
        },
    } as unknown as DurableObjectNamespace;
}

function createAnomalyQueue() {
    const messages: unknown[] = [];
    return {
        queue: {
            async send(message: unknown) {
                messages.push(message);
            },
        } as never,
        messages,
    };
}

describe('relay proxy faucet queue worker', () => {
    it('acks successful funding messages', async () => {
        const { batch, state } = createBatch(['0x1111111111111111111111111111111111111111']);
        const anomalies = createAnomalyQueue();

        await consumeFaucetBatch(batch, {
            ANOMALY_QUEUE: anomalies.queue,
            FAUCET_DO: createDO({
                ok: true,
                result: {
                    hashes: { 84532: '0xhash' },
                    status: 'fulfilled',
                },
            }),
        });

        expect(state[0].ackCount).toBe(1);
        expect(state[0].retryCount).toBe(0);
        expect(anomalies.messages).toHaveLength(0);
    });

    it('emits anomaly for failed funding and still acks message', async () => {
        const userId = '0x2222222222222222222222222222222222222222';
        const { batch, state } = createBatch([userId]);
        const anomalies = createAnomalyQueue();

        await consumeFaucetBatch(batch, {
            ANOMALY_QUEUE: anomalies.queue,
            FAUCET_DO: createDO({
                ok: true,
                result: {
                    hashes: {},
                    status: 'partial',
                },
            }),
        });

        expect(state[0].ackCount).toBe(1);
        expect(state[0].retryCount).toBe(0);
        expect(anomalies.messages).toHaveLength(1);
        expect(anomalies.messages[0]).toMatchObject({
            type: 'anomaly_faucet_funding_failed',
            userId,
        });
    });
});

import { resolveRequiredEnvValue } from '../../shared/http';
import type { Env } from '../../shared/types';

const ALCHEMY_VARIABLES_BASE = 'https://dashboard.alchemy.com/api/graphql/variables';
const VARIABLE_NAME = 'accumulators';

/**
 * Durable Object that atomically manages the reference count for a single
 * accumulator address in the Alchemy Custom Webhook variable list.
 *
 * Each instance is keyed by the accumulator address. All fetch() operations
 * are serialized by Cloudflare — eliminating TOCTOU races between concurrent
 * HTTP handlers (adding TXs) and Queue consumers (dispatching TXs).
 *
 * Routes:
 *   POST /increment — Increments count. Adds to Alchemy if 0 -> 1.
 *   POST /decrement — Decrements count. Removes from Alchemy if 1 -> 0.
 *   GET  /count     — Returns current ref count (debugging).
 */
export class AccumulatorWebhookTracker implements DurableObject {
    private state: DurableObjectState;
    private env: Env;

    constructor(state: DurableObjectState, env: Env) {
        this.state = state;
        this.env = env;
    }

    async fetch(request: Request): Promise<Response> {
        const url = new URL(request.url);

        switch (url.pathname) {
            case '/increment':
                return this.increment(request);
            case '/decrement':
                return this.decrement();
            case '/count':
                return this.getCount();
            default:
                return new Response('Not found', { status: 404 });
        }
    }

    private async increment(request: Request): Promise<Response> {
        const body = (await request.json()) as { accumulatorAddress: string };
        const address = body.accumulatorAddress;

        const storedAddress = await this.state.storage.get<string>('address');
        if (!storedAddress) {
            await this.state.storage.put('address', address);
        }

        const count = (await this.state.storage.get<number>('count')) ?? 0;
        const newCount = count + 1;
        await this.state.storage.put('count', newCount);

        if (count === 0) {
            await this.addToAlchemy(address);
        }

        return Response.json({ count: newCount, added: count === 0 });
    }

    private async decrement(): Promise<Response> {
        const count = (await this.state.storage.get<number>('count')) ?? 0;
        if (count === 0) {
            return Response.json({ count: 0, removed: false });
        }

        const newCount = count - 1;
        await this.state.storage.put('count', newCount);

        if (newCount === 0) {
            const address = await this.state.storage.get<string>('address');
            if (address) {
                await this.removeFromAlchemy(address);
            }
        }

        return Response.json({ count: newCount, removed: newCount === 0 });
    }

    private async getCount(): Promise<Response> {
        const count = (await this.state.storage.get<number>('count')) ?? 0;
        const address = (await this.state.storage.get<string>('address')) ?? '';
        return Response.json({ count, address });
    }

    private async addToAlchemy(address: string): Promise<void> {
        const apiKey = resolveRequiredEnvValue(
            this.env.ALCHEMY_WEBHOOK_API_KEY,
            'ALCHEMY_WEBHOOK_API_KEY',
        );

        try {
            const response = await fetch(`${ALCHEMY_VARIABLES_BASE}/${VARIABLE_NAME}`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-Alchemy-Token': apiKey,
                },
                body: JSON.stringify({ items: [address] }),
            });

            if (!response.ok) {
                const text = await response.text();
                console.error(
                    `[webhook-tracker.do] Alchemy add failed (${response.status}): ${text}`,
                );
            }
        } catch (error) {
            console.error('[webhook-tracker.do] Alchemy add error:', error);
        }
    }

    private async removeFromAlchemy(address: string): Promise<void> {
        const apiKey = resolveRequiredEnvValue(
            this.env.ALCHEMY_WEBHOOK_API_KEY,
            'ALCHEMY_WEBHOOK_API_KEY',
        );

        try {
            const response = await fetch(`${ALCHEMY_VARIABLES_BASE}/${VARIABLE_NAME}`, {
                method: 'PATCH',
                headers: {
                    'Content-Type': 'application/json',
                    'X-Alchemy-Token': apiKey,
                },
                body: JSON.stringify({ delete: [address] }),
            });

            if (!response.ok) {
                const text = await response.text();
                console.error(
                    `[webhook-tracker.do] Alchemy remove failed (${response.status}): ${text}`,
                );
            }
        } catch (error) {
            console.error('[webhook-tracker.do] Alchemy remove error:', error);
        }
    }
}

/** Resolves a mapped Durable Object stub for a specific accumulator address. */
export function getWebhookTracker(accumulatorAddress: string, env: Env): DurableObjectStub {
    const id = env.WEBHOOK_TRACKER.idFromName(accumulatorAddress);
    return env.WEBHOOK_TRACKER.get(id);
}

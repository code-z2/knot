/**
 * Lightweight mock factories for Cloudflare Workers bindings.
 * These simulate KV, Queue, and Durable Object behavior in-memory
 * without requiring @cloudflare/vitest-pool-workers.
 */
import { vi } from 'vitest';

import type { Env } from '../shared/types';

// ---------------------------------------------------------------------------
// KV Namespace
// ---------------------------------------------------------------------------

export function createMockKV(seed: Record<string, string> = {}): KVNamespace {
    const store = new Map<string, { value: string; expiration?: number }>(
        Object.entries(seed).map(([k, v]) => [k, { value: v }]),
    );

    return {
        get: vi.fn(async (key: string) => store.get(key)?.value ?? null),
        put: vi.fn(async (key: string, value: string, opts?: { expirationTtl?: number }) => {
            store.set(key, { value, expiration: opts?.expirationTtl });
        }),
        delete: vi.fn(async (key: string) => {
            store.delete(key);
        }),
        list: vi.fn(async (opts?: { prefix?: string; cursor?: string }) => {
            const prefix = opts?.prefix ?? '';
            const keys = [...store.keys()]
                .filter((k) => k.startsWith(prefix))
                .map((name) => ({
                    name,
                    expiration: store.get(name)?.expiration,
                    metadata: null,
                }));
            return {
                keys,
                list_complete: true,
                cursor: undefined,
                cacheStatus: null,
            };
        }),
        getWithMetadata: vi.fn(),
    } as unknown as KVNamespace;
}

// ---------------------------------------------------------------------------
// Queue
// ---------------------------------------------------------------------------

export interface MockQueue<T = unknown> {
    sent: T[];
    send: ReturnType<typeof vi.fn>;
    sendBatch: ReturnType<typeof vi.fn>;
}

export function createMockQueue<T = unknown>(): Queue<T> & MockQueue<T> {
    const sent: T[] = [];
    return {
        sent,
        send: vi.fn(async (message: T) => {
            sent.push(message);
        }),
        sendBatch: vi.fn(async (messages: Iterable<{ body: T }>) => {
            for (const m of messages) sent.push(m.body);
        }),
    } as unknown as Queue<T> & MockQueue<T>;
}

// ---------------------------------------------------------------------------
// MessageBatch
// ---------------------------------------------------------------------------

export interface MockMessage<T> {
    body: T;
    ack: ReturnType<typeof vi.fn>;
    retry: ReturnType<typeof vi.fn>;
}

export function createMockBatch<T>(messages: T[]): MessageBatch<T> {
    const mocks: MockMessage<T>[] = messages.map((body) => ({
        body,
        ack: vi.fn(),
        retry: vi.fn(),
    }));
    return {
        messages: mocks,
        queue: 'test-queue',
        ackAll: vi.fn(),
        retryAll: vi.fn(),
    } as unknown as MessageBatch<T>;
}

// ---------------------------------------------------------------------------
// Durable Object Stub
// ---------------------------------------------------------------------------

export function createMockDOStub(
    handler?: (request: Request) => Promise<Response>,
): DurableObjectStub {
    const defaultHandler = async () => new Response('ok', { status: 200 });
    return {
        fetch: vi.fn(handler ?? defaultHandler),
    } as unknown as DurableObjectStub;
}

export function createMockDONamespace(stub?: DurableObjectStub): DurableObjectNamespace {
    const mockStub = stub ?? createMockDOStub();
    return {
        idFromName: vi.fn(() => ({ toString: () => 'mock-do-id' })),
        get: vi.fn(() => mockStub),
        newUniqueId: vi.fn(),
        idFromString: vi.fn(),
        jurisdiction: vi.fn(),
    } as unknown as DurableObjectNamespace;
}

// ---------------------------------------------------------------------------
// Full Env Factory
// ---------------------------------------------------------------------------

export function createMockEnv(overrides: Partial<Env> = {}): Env {
    return {
        GAS_TANK_KV: createMockKV(),
        DEFERRED_RELAY_KV: createMockKV(),
        RELAY_BATCH_QUEUE: createMockQueue() as unknown as Queue,
        ALERTS_QUEUE: createMockQueue() as unknown as Queue,
        WEBHOOK_TRACKER: createMockDONamespace(),
        RELAY_AUTH_TOKEN: 'test-token',
        PINATA_JWT: 'test-jwt',
        PINATA_GATEWAY_BASE_URL: 'https://gateway.pinata.cloud',
        PINATA_GROUP_CONFIG: {},
        ...overrides,
    } as Env;
}

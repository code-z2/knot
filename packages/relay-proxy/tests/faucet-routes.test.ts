import { describe, expect, it } from 'bun:test';

import { FaucetDurableObject } from '../src/durable-objects/faucet';
import type { DOResponse, FaucetDOResult, RpcFailure, RpcSuccess } from '../src/types';
import { createTestApp } from './helpers/app';
import { registerUser } from './helpers/auth-flow';
import { jsonHeaders, readJson } from './helpers/http';

const FAUCET_USER = '0x9999999999999999999999999999999999999999';

function faucetRpc(params: object = {}) {
    return {
        id: 'faucet_request',
        jsonrpc: '2.0',
        method: 'knot_faucetRequest',
        params,
    };
}

function lowAuthHeaders(accessToken: string) {
    return {
        authorization: `Bearer ${accessToken}`,
        ...jsonHeaders(),
    };
}

function createUserD1(initialConsumed = false) {
    const users = new Map<string, { faucetConsumed: number; status: 'active' | 'revoked' }>([
        [
            FAUCET_USER,
            {
                faucetConsumed: initialConsumed ? 1 : 0,
                status: 'active',
            },
        ],
    ]);

    return {
        prepare(query: string) {
            let values: readonly unknown[] = [];

            return {
                bind(...nextValues: readonly unknown[]) {
                    values = nextValues;
                    return this;
                },
                async first<Result>() {
                    const userId = values[0];
                    if (typeof userId !== 'string') {
                        return null;
                    }

                    const user = users.get(userId);
                    if (!user || user.status !== 'active') {
                        return null;
                    }

                    if (query.includes('select faucet_consumed')) {
                        return {
                            faucetConsumed: user.faucetConsumed,
                        } as Result;
                    }

                    return null;
                },
                async run() {
                    const userId = values[0];
                    const user = typeof userId === 'string' ? users.get(userId) : null;

                    if (!query.includes('update users') || !user || user.status !== 'active') {
                        return { meta: { changes: 0 } };
                    }

                    if (user.faucetConsumed === 1) {
                        return { meta: { changes: 0 } };
                    }

                    user.faucetConsumed = 1;
                    return { meta: { changes: 1 } };
                },
            };
        },
        users,
    };
}

function createFaucetDO(response: DOResponse<FaucetDOResult>) {
    const calls: string[] = [];

    return {
        namespace: {
            idFromName(name: string) {
                calls.push(name);
                return name as never;
            },
            get() {
                return {
                    async fetch() {
                        return Response.json(response);
                    },
                };
            },
        },
        calls,
    };
}

function createFaucetEnv(input: { db: ReturnType<typeof createUserD1>; faucetDO?: ReturnType<typeof createFaucetDO> }) {
    return {
        AUTH_DB: input.db as unknown as D1Database,
        AUTH_KV: {} as never,
        FAUCET_DO: (input.faucetDO?.namespace ?? {}) as unknown as DurableObjectNamespace,
    } as never;
}

async function withSilencedConsoleError<Result>(fn: () => Promise<Result>): Promise<Result> {
    const original = console.error;
    console.error = () => undefined;
    try {
        return await fn();
    } finally {
        console.error = original;
    }
}

async function registerFaucetUser(app: ReturnType<typeof createTestApp>['app']) {
    const { verifyBody } = await registerUser(app, {
        appAttestKeyId: 'attest-key-faucet',
        credentialId: 'credential-faucet',
        userId: FAUCET_USER,
    });

    return verifyBody.result;
}

describe('relay proxy faucet route', () => {
    it('fails fast from D1 without waking the Faucet DO when already consumed', async () => {
        const db = createUserD1(true);
        const faucetDO = createFaucetDO({
            ok: true,
            result: {
                funded: true,
                hashes: { 84532: '0x1' },
            },
        });
        const { app } = createTestApp();
        const session = await registerFaucetUser(app);

        const response = await app.request(
            'http://localhost/v1/faucet/request',
            {
                body: JSON.stringify(faucetRpc()),
                headers: lowAuthHeaders(session.accessToken),
                method: 'POST',
            },
            createFaucetEnv({ db, faucetDO }),
        );

        expect(response.status).toBe(400);
        expect(faucetDO.calls).toEqual([]);
        expect(await readJson<RpcFailure>(response)).toMatchObject({
            error: {
                reason: 'faucet_already_consumed',
            },
        });
    });

    it('wakes the Faucet DO for first-time requests', async () => {
        const db = createUserD1(false);
        const faucetDO = createFaucetDO({
            ok: true,
            result: {
                funded: true,
                hashes: { 84532: '0xfacade' },
            },
        });
        const { app } = createTestApp();
        const session = await registerFaucetUser(app);

        const response = await app.request(
            'http://localhost/v1/faucet/request',
            {
                body: JSON.stringify(faucetRpc()),
                headers: lowAuthHeaders(session.accessToken),
                method: 'POST',
            },
            createFaucetEnv({ db, faucetDO }),
        );

        expect(response.status).toBe(200);
        expect(faucetDO.calls).toEqual([FAUCET_USER]);
        expect(await readJson<RpcSuccess<Record<string, unknown>>>(response)).toEqual({
            id: 'faucet_request',
            jsonrpc: '2.0',
            result: {
                funded: true,
                hashes: { 84532: '0xfacade' },
            },
        });
    });

    it('rejects client-provided faucet parameters', async () => {
        const db = createUserD1(false);
        const faucetDO = createFaucetDO({
            ok: true,
            result: {
                funded: true,
                hashes: { 84532: '0xfacade' },
            },
        });
        const { app } = createTestApp();
        const session = await registerFaucetUser(app);

        const response = await app.request(
            'http://localhost/v1/faucet/request',
            {
                body: JSON.stringify(faucetRpc({ chainId: 84532 })),
                headers: lowAuthHeaders(session.accessToken),
                method: 'POST',
            },
            createFaucetEnv({ db, faucetDO }),
        );

        expect(response.status).toBe(400);
        expect(faucetDO.calls).toEqual([]);
        expect(await readJson<RpcFailure>(response)).toMatchObject({
            error: {
                reason: 'invalid_params',
            },
        });
    });
});

describe('Faucet Durable Object', () => {
    it('consumes the D1 boolean before best-effort funding', async () => {
        const db = createUserD1(false);
        const faucet = new FaucetDurableObject({} as never, createFaucetEnv({ db }) as never);

        const response = await withSilencedConsoleError(() =>
            faucet.fetch(
                new Request(`https://faucet.local/request?userId=${FAUCET_USER}`, {
                    method: 'POST',
                }),
            ),
        );

        expect(response.status).toBe(200);
        expect(db.users.get(FAUCET_USER)?.faucetConsumed).toBe(1);
        const body = (await response.json()) as DOResponse<FaucetDOResult>;

        expect(body).toEqual({
            ok: true,
            result: {
                funded: false,
                hashes: {},
            },
        });
    });

    it('allows only one consume attempt for concurrent requests', async () => {
        const db = createUserD1(false);
        const faucet = new FaucetDurableObject({} as never, createFaucetEnv({ db }) as never);
        const request = () =>
            faucet.fetch(
                new Request(`https://faucet.local/request?userId=${FAUCET_USER}`, {
                    method: 'POST',
                }),
            );

        const [first, second] = await withSilencedConsoleError(() => Promise.all([request(), request()]));
        const results = (await Promise.all([first.json(), second.json()])) as DOResponse<FaucetDOResult>[];

        expect(results.filter((result) => result.ok === true)).toHaveLength(1);
        expect(results.filter((result) => result.ok === false)).toEqual([
            {
                ok: false,
                reason: 'faucet_already_consumed',
            },
        ]);
        expect(db.users.get(FAUCET_USER)?.faucetConsumed).toBe(1);
    });
});

import { describe, expect, it } from 'bun:test';
import type { Address, Call, Hex } from 'viem';

import type { BundlerClient, GasClient, GasProfileRecord, RpcFailure, RpcSuccess } from '../src/types';
import { uint } from '../src/utils';
import { createTestApp } from './helpers/app';
import { registerUser } from './helpers/auth-flow';
import { jsonHeaders, readJson } from './helpers/http';

type GasProfileRow = {
    minimumAllowedUsdc: Hex;
    overdraftEligible: number;
    overdraftEnabled: number;
    overdraftLocked: number;
    overdraftOutstandingUsdc: Hex;
    outstandingDebtUsdc: Hex;
    updatedAt: number;
    userId: string;
};

type GasClientCalls = {
    cosign: unknown[];
    decrementOutstandingDebt: unknown[];
    encodeDebitCall: unknown[];
    submitDebitCalls: unknown[];
};

const GAS_USER = '0x5555555555555555555555555555555555555555';
const GAS_TANK_ADDRESS = '0x6666666666666666666666666666666666666666';
const WITHDRAW_TO = '0x7777777777777777777777777777777777777777';

function createMockKV() {
    const records = new Map<string, string>();

    return {
        async get(key: string) {
            return records.get(key) ?? null;
        },
        async put(key: string, value: string) {
            records.set(key, value);
        },
        records,
    };
}

function createGasProfile(userId: string, overrides: Partial<GasProfileRecord> = {}): GasProfileRecord {
    return {
        minimumAllowedUsdc: uint.zero,
        overdraftEligible: false,
        overdraftEnabled: false,
        overdraftLocked: false,
        overdraftOutstandingUsdc: uint.zero,
        outstandingDebtUsdc: uint.zero,
        updatedAt: 0,
        userId,
        ...overrides,
    };
}

function toGasProfileRow(profile: GasProfileRecord): GasProfileRow {
    return {
        minimumAllowedUsdc: profile.minimumAllowedUsdc.hex,
        overdraftEligible: Number(profile.overdraftEligible),
        overdraftEnabled: Number(profile.overdraftEnabled),
        overdraftLocked: Number(profile.overdraftLocked),
        overdraftOutstandingUsdc: profile.overdraftOutstandingUsdc.hex,
        outstandingDebtUsdc: profile.outstandingDebtUsdc.hex,
        updatedAt: profile.updatedAt,
        userId: profile.userId,
    };
}

function createMockD1(initialProfiles: readonly GasProfileRecord[] = []) {
    const profiles = new Map(initialProfiles.map((profile) => [profile.userId, toGasProfileRow(profile)]));

    return {
        prepare(query: string) {
            let values: readonly unknown[] = [];

            return {
                bind(...nextValues: readonly unknown[]) {
                    values = nextValues;
                    return this;
                },
                async first<Result>() {
                    if (!query.includes('select')) {
                        return null;
                    }

                    const userId = values[0];
                    if (typeof userId !== 'string') {
                        return null;
                    }

                    return (profiles.get(userId) ?? null) as Result | null;
                },
                async run() {
                    if (!query.includes('insert into gas_profiles')) {
                        return {};
                    }

                    const userId = values[0];
                    if (typeof userId !== 'string') {
                        return {};
                    }

                    profiles.set(userId, {
                        minimumAllowedUsdc: values[1] as Hex,
                        overdraftEligible: values[2] as number,
                        overdraftEnabled: values[3] as number,
                        overdraftLocked: values[4] as number,
                        overdraftOutstandingUsdc: values[5] as Hex,
                        outstandingDebtUsdc: values[6] as Hex,
                        updatedAt: values[7] as number,
                        userId,
                    });

                    return {};
                },
            };
        },
        profiles,
    };
}

function createGasEnv(input: { db: ReturnType<typeof createMockD1>; usageKV?: ReturnType<typeof createMockKV> }) {
    return {
        ANOMALY_QUEUE: {} as never,
        AUTH_DB: {} as never,
        AUTH_KV: {} as never,
        BUNDLER_API_KEY: 'bundler-api-key' as never,
        GAS_TANK_DB: input.db as unknown as D1Database,
        GAS_TANK_DO: {} as never,
        GAS_USAGE_KV: (input.usageKV ?? createMockKV()) as unknown as KVNamespace,
        JSON_RPC_API_KEY: 'rpc-api-key' as never,
        KNOT_APPLE_BUNDLE_ID: 'app.knot.ios',
        KNOT_APPLE_TEAM_ID: 'TEAM123456',
        KNOT_APP_ATTEST_ALLOW_DEVELOPMENT: 'true',
        KNOT_RP_ID: 'knot.fi',
        KNOT_RP_NAME: 'Knot',
        KNOT_RP_ORIGIN: 'https://knot.fi',
        PINATA_GATEWAY_BASE_URL: 'https://gateway.pinata.cloud',
        PINATA_IMAGE_GROUP_ID: 'group',
        PINATA_JWT: 'jwt',
        RELAY_KV: {} as never,
        RELAY_QUEUE: {} as never,
        SERVER_KEY: 'server-key' as never,
        TREASURY_ADDRESS: '0x8888888888888888888888888888888888888888',
    } as never;
}

function createBundler(calls?: GasClientCalls) {
    return {
        account: {
            authorization: {
                account: {
                    async signAuthorization() {
                        return {
                            address: '0x9999999999999999999999999999999999999999',
                            chainId: 8453,
                            nonce: 0,
                            r: '0x0',
                            s: '0x0',
                            yParity: 0,
                        };
                    },
                },
            },
            entryPoint: {
                address: '0x0000000071727de22e5e9d8baf0edac6f37da032',
            },
            async signUserOperation() {
                return '0xsig';
            },
        },
        chain: {
            environment: 'mainnet',
            id: 8453,
        },
        async prepareUserOperation(input: { calls: readonly Call[] }) {
            calls?.submitDebitCalls.push(input.calls);
            return {
                callData: '0x',
                callGasLimit: 1n,
                maxFeePerGas: 0n,
                maxPriorityFeePerGas: 0n,
                nonce: 0n,
                preVerificationGas: 1n,
                sender: GAS_USER,
                signature: '0x',
                verificationGasLimit: 1n,
            };
        },
        async sendUserOperationSync() {
            return {
                success: true,
                userOpHash: '0xhash',
            };
        },
    } as unknown as BundlerClient;
}

function createGasClient(
    input: {
        balance?: bigint;
        gasProfile?: GasProfileRecord;
        provider?: ReturnType<GasClient['getGasProvider']>;
    } = {},
) {
    const calls: GasClientCalls = {
        cosign: [],
        decrementOutstandingDebt: [],
        encodeDebitCall: [],
        submitDebitCalls: [],
    };
    const provider = input.provider ?? {
        gasTankAddress: GAS_TANK_ADDRESS,
        kind: 'knot' as const,
    };

    const gasClient = {
        async admitExposure() {
            return { pendingExposureUsdc: '0x0' };
        },
        async cosign(userId: Address, params: { amount: uint; deadline: number; to: Address }) {
            calls.cosign.push([userId, params]);
            return '0xabcdef';
        },
        async ctx(userId: Address) {
            return {
                balanceUsdc: uint(input.balance ?? 0n),
                gasProfile: input.gasProfile ?? createGasProfile(userId),
                pendingExposureUsdc: uint.zero,
                provider,
            };
        },
        async decrementOutstandingDebt(userId: Address, amountUsdc: uint) {
            calls.decrementOutstandingDebt.push([userId, amountUsdc.hex]);
            return { outstandingDebtUsdc: '0x0' };
        },
        async decrementPendingExposure() {
            return { pendingExposureUsdc: '0x0' };
        },
        async encodeDebitCall(userId: Address, amountUsdc: uint) {
            calls.encodeDebitCall.push([userId, amountUsdc.hex]);
            return [
                {
                    data: '0x',
                    to: GAS_TANK_ADDRESS,
                } satisfies Call,
            ];
        },
        async getGasBalance() {
            return input.balance ?? 0n;
        },
        getGasProvider() {
            return provider;
        },
        getGasTankAddress() {
            return GAS_TANK_ADDRESS;
        },
        async getGasWithdrawalNonce() {
            return 7n;
        },
        async getRecord() {
            return { pendingExposureUsdc: '0x0' };
        },
        async incrementOutstandingDebt() {
            return { outstandingDebtUsdc: '0x0' };
        },
        async incrementPendingExposure() {
            return { pendingExposureUsdc: '0x0' };
        },
        async submitDebitCalls(callsInput: readonly Call[]) {
            calls.submitDebitCalls.push(callsInput);
        },
    } as unknown as GasClient;

    return { calls, gasClient };
}

function gasRpc(id: string, method: string, params: object) {
    return {
        id,
        jsonrpc: '2.0',
        method,
        params,
    };
}

function lowAuthHeaders(accessToken: string) {
    return {
        authorization: `Bearer ${accessToken}`,
        ...jsonHeaders(),
    };
}

function highAuthHeaders(accessToken: string, appAttestKeyId: string, nonce: string) {
    return {
        authorization: `Bearer ${accessToken}`,
        'x-knot-app-attest-assertion': 'assertion:gas',
        'x-knot-app-attest-key-id': appAttestKeyId,
        'x-knot-nonce': nonce,
        'x-knot-timestamp': String(Date.now()),
        ...jsonHeaders(),
    };
}

async function registerGasUser(app: ReturnType<typeof createTestApp>['app']) {
    const { verifyBody } = await registerUser(app, {
        appAttestKeyId: 'attest-key-gas',
        credentialId: 'credential-gas',
        userId: GAS_USER,
    });

    return verifyBody.result;
}

describe('relay proxy gas routes', () => {
    it('returns gas status with JSON-safe uint values and provider data', async () => {
        const profile = createGasProfile(GAS_USER, {
            minimumAllowedUsdc: uint('0x5'),
            overdraftEligible: true,
            overdraftEnabled: true,
            overdraftOutstandingUsdc: uint('0x2'),
            outstandingDebtUsdc: uint('0xff'),
            updatedAt: 123,
        });
        const db = createMockD1([profile]);
        const { gasClient } = createGasClient({ balance: 100n });
        const { app } = createTestApp({
            bundler: createBundler(),
            gasClient,
        });
        const session = await registerGasUser(app);

        const response = await app.request(
            'http://localhost/v1/gas',
            {
                method: 'POST',
                headers: lowAuthHeaders(session.accessToken),
                body: JSON.stringify(gasRpc('gas_status', 'knot_gasStatus', { environment: 'mainnet' })),
            },
            createGasEnv({ db }),
        );

        expect(response.status).toBe(200);
        expect(await readJson<RpcSuccess<Record<string, unknown>>>(response)).toEqual({
            id: 'gas_status',
            jsonrpc: '2.0',
            result: {
                balanceUsdc: {
                    decimals: 6,
                    formatted: '0.0001',
                    hex: '0x64',
                    value: '100',
                },
                minimumAllowedUsdc: {
                    decimals: 6,
                    formatted: '0.000005',
                    hex: '0x5',
                    value: '5',
                },
                overdraftEligible: true,
                overdraftEnabled: true,
                overdraftLocked: false,
                overdraftOutstandingUsdc: {
                    decimals: 6,
                    formatted: '0.000002',
                    hex: '0x2',
                    value: '2',
                },
                provider: {
                    gasTankAddress: GAS_TANK_ADDRESS,
                    kind: 'knot',
                },
            },
        });
    });

    it('returns empty gas history for the requested window', async () => {
        const db = createMockD1();
        const { app } = createTestApp({
            bundler: createBundler(),
        });
        const session = await registerGasUser(app);

        const response = await app.request(
            'http://localhost/v1/gas/history',
            {
                method: 'POST',
                headers: lowAuthHeaders(session.accessToken),
                body: JSON.stringify(gasRpc('gas_history', 'knot_gasHistory', { window: '6m' })),
            },
            createGasEnv({ db }),
        );

        expect(response.status).toBe(200);
        expect(await readJson<RpcSuccess<Record<string, unknown>>>(response)).toEqual({
            id: 'gas_history',
            jsonrpc: '2.0',
            result: {
                chains: {},
                totalUsdc: {
                    decimals: 6,
                    formatted: '0',
                    hex: '0x0',
                    value: '0',
                },
                updatedAt: '1970-01-01T00:00:00.000Z',
                window: '6m',
            },
        });
    });

    it('enables overdraft for eligible users', async () => {
        const db = createMockD1([
            createGasProfile(GAS_USER, {
                overdraftEligible: true,
            }),
        ]);
        const { app } = createTestApp({
            bundler: createBundler(),
        });
        const session = await registerGasUser(app);

        const response = await app.request(
            'http://localhost/v1/gas/overdraft',
            {
                method: 'POST',
                headers: highAuthHeaders(session.accessToken, session.appAttestKeyId, 'nonce-overdraft-enable'),
                body: JSON.stringify(gasRpc('gas_overdraft_enable', 'knot_gasOverdraftUpdate', { action: 'enable' })),
            },
            createGasEnv({ db }),
        );

        expect(response.status).toBe(200);
        const body = await readJson<RpcSuccess<{ overdraftEnabled: boolean }>>(response);
        expect(body.result.overdraftEnabled).toBe(true);
    });

    it('rejects overdraft enablement when the user is not eligible', async () => {
        const db = createMockD1([createGasProfile(GAS_USER)]);
        const { app } = createTestApp({
            bundler: createBundler(),
        });
        const session = await registerGasUser(app);

        const response = await app.request(
            'http://localhost/v1/gas/overdraft',
            {
                method: 'POST',
                headers: highAuthHeaders(session.accessToken, session.appAttestKeyId, 'nonce-overdraft-ineligible'),
                body: JSON.stringify(
                    gasRpc('gas_overdraft_ineligible', 'knot_gasOverdraftUpdate', { action: 'enable' }),
                ),
            },
            createGasEnv({ db }),
        );

        expect(response.status).toBe(400);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'gas_overdraft_ineligible',
            jsonrpc: '2.0',
            error: {
                code: -32000,
                message: 'overdraft_not_eligible',
                reason: 'overdraft_not_eligible',
            },
        });
    });

    it('rejects overdraft disablement when overdraft is locked', async () => {
        const db = createMockD1([
            createGasProfile(GAS_USER, {
                overdraftEnabled: true,
                overdraftLocked: true,
            }),
        ]);
        const { app } = createTestApp({
            bundler: createBundler(),
        });
        const session = await registerGasUser(app);

        const response = await app.request(
            'http://localhost/v1/gas/overdraft',
            {
                method: 'POST',
                headers: highAuthHeaders(session.accessToken, session.appAttestKeyId, 'nonce-overdraft-locked'),
                body: JSON.stringify(gasRpc('gas_overdraft_locked', 'knot_gasOverdraftUpdate', { action: 'disable' })),
            },
            createGasEnv({ db }),
        );

        expect(response.status).toBe(400);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'gas_overdraft_locked',
            jsonrpc: '2.0',
            error: {
                code: -32000,
                message: 'overdraft_locked',
                reason: 'overdraft_locked',
            },
        });
    });

    it('cosigns a debt-free withdrawal for the full balance', async () => {
        const db = createMockD1();
        const { calls, gasClient } = createGasClient({
            balance: 10n,
            gasProfile: createGasProfile(GAS_USER),
        });
        const { app } = createTestApp({
            bundler: createBundler(calls),
            gasClient,
        });
        const session = await registerGasUser(app);

        const response = await app.request(
            'http://localhost/v1/gas/withdraw',
            {
                method: 'POST',
                headers: highAuthHeaders(session.accessToken, session.appAttestKeyId, 'nonce-withdraw-clean'),
                body: JSON.stringify(
                    gasRpc('gas_withdraw_clean', 'knot_gasWithdraw', {
                        deadline: 1_900_000_000,
                        to: WITHDRAW_TO,
                    }),
                ),
            },
            createGasEnv({ db }),
        );

        expect(response.status).toBe(200);
        expect(calls.encodeDebitCall).toEqual([]);
        expect(calls.submitDebitCalls).toEqual([]);
        expect(calls.decrementOutstandingDebt).toEqual([]);
        expect(calls.cosign).toEqual([
            [
                GAS_USER,
                {
                    amount: expect.objectContaining({ hex: '0xa' }),
                    deadline: 1_900_000_000,
                    to: WITHDRAW_TO,
                },
            ],
        ]);
        expect(await readJson<RpcSuccess<Record<string, unknown>>>(response)).toEqual({
            id: 'gas_withdraw_clean',
            jsonrpc: '2.0',
            result: {
                amount: {
                    decimals: 6,
                    formatted: '0.00001',
                    hex: '0xa',
                    value: '10',
                },
                cosignerSig: '0xabcdef',
                gasTankAddress: GAS_TANK_ADDRESS,
                nonce: '0x7',
            },
        });
    });

    it('collects outstanding debt before cosigning the remaining balance', async () => {
        const db = createMockD1();
        const { calls, gasClient } = createGasClient({
            balance: 10n,
            gasProfile: createGasProfile(GAS_USER, {
                outstandingDebtUsdc: uint('0x4'),
            }),
        });
        const { app } = createTestApp({
            bundler: createBundler(calls),
            gasClient,
        });
        const session = await registerGasUser(app);

        const response = await app.request(
            'http://localhost/v1/gas/withdraw',
            {
                method: 'POST',
                headers: highAuthHeaders(session.accessToken, session.appAttestKeyId, 'nonce-withdraw-collect'),
                body: JSON.stringify(
                    gasRpc('gas_withdraw_collect', 'knot_gasWithdraw', {
                        deadline: 1_900_000_000,
                        to: WITHDRAW_TO,
                    }),
                ),
            },
            createGasEnv({ db }),
        );

        expect(response.status).toBe(200);
        expect(calls.encodeDebitCall).toEqual([[GAS_USER, '0x4']]);
        expect(calls.submitDebitCalls).toHaveLength(1);
        expect(calls.decrementOutstandingDebt).toEqual([[GAS_USER, '0x4']]);
        expect(calls.cosign).toEqual([
            [
                GAS_USER,
                {
                    amount: expect.objectContaining({ hex: '0x6' }),
                    deadline: 1_900_000_000,
                    to: WITHDRAW_TO,
                },
            ],
        ]);
    });

    it('rejects withdrawal when collection cannot clear outstanding debt', async () => {
        const db = createMockD1();
        const { calls, gasClient } = createGasClient({
            balance: 3n,
            gasProfile: createGasProfile(GAS_USER, {
                outstandingDebtUsdc: uint('0xa'),
            }),
        });
        const { app } = createTestApp({
            bundler: createBundler(),
            gasClient,
        });
        const session = await registerGasUser(app);

        const response = await app.request(
            'http://localhost/v1/gas/withdraw',
            {
                method: 'POST',
                headers: highAuthHeaders(session.accessToken, session.appAttestKeyId, 'nonce-withdraw-pending'),
                body: JSON.stringify(
                    gasRpc('gas_withdraw_pending', 'knot_gasWithdraw', {
                        deadline: 1_900_000_000,
                        to: WITHDRAW_TO,
                    }),
                ),
            },
            createGasEnv({ db }),
        );

        expect(response.status).toBe(400);
        expect(calls.encodeDebitCall).toEqual([[GAS_USER, '0x3']]);
        expect(calls.decrementOutstandingDebt).toEqual([[GAS_USER, '0x3']]);
        expect(calls.cosign).toEqual([]);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'gas_withdraw_pending',
            jsonrpc: '2.0',
            error: {
                code: -32000,
                message: 'pending_debit_outstanding',
                reason: 'pending_debit_outstanding',
            },
        });
    });

    it('rejects withdrawal for unsupported gas providers', async () => {
        const db = createMockD1();
        const { gasClient } = createGasClient({
            balance: 10n,
            gasProfile: createGasProfile(GAS_USER),
            provider: { kind: 'self' },
        });
        const { app } = createTestApp({
            bundler: createBundler(),
            gasClient,
        });
        const session = await registerGasUser(app);

        const response = await app.request(
            'http://localhost/v1/gas/withdraw',
            {
                method: 'POST',
                headers: highAuthHeaders(session.accessToken, session.appAttestKeyId, 'nonce-withdraw-provider'),
                body: JSON.stringify(
                    gasRpc('gas_withdraw_provider', 'knot_gasWithdraw', {
                        deadline: 1_900_000_000,
                        to: WITHDRAW_TO,
                    }),
                ),
            },
            createGasEnv({ db }),
        );

        expect(response.status).toBe(400);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'gas_withdraw_provider',
            jsonrpc: '2.0',
            error: {
                code: -32000,
                message: 'unsupported_gas_provider',
                reason: 'unsupported_gas_provider',
            },
        });
    });
});

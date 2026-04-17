import { describe, expect, it } from 'bun:test';

import { createBundlerClient } from '../src/services/bundler';
import { CHAIN_REGISTRY } from '../src/constants/chains';
import type { CloudflareBindings, CreateAppOptions } from '../src/types';

describe('relay proxy bundler service', () => {
    it('returns the injected options.bundler client when present', async () => {
        const chain = CHAIN_REGISTRY[84532];
        const sentinel = {
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
                return '0xhash';
            },
            async sendUserOperationBatch() {
                return [];
            },
            async sendUserOperationSync() {
                return {} as never;
            },
        };
        const options: CreateAppOptions = {
            bundler: sentinel as never,
        };
        const client = await createBundlerClient(
            {
                ANOMALY_QUEUE: {} as never,
                ACCOUNT_IMPLEMENTATION: '0x0000000000000000000000000000000000000000',
                ACCUMULATOR_MODULE: '0x0000000000000000000000000000000000000000',
                AUTH_DB: {} as never,
                AUTH_KV: {} as never,
                BUNDLER_API_KEY: 'api-key' as never,
                CONSUMER_HUB: '0x0000000000000000000000000000000000000000',
                CROSS_CHAIN_EXECUTOR_MODULE: '0x0000000000000000000000000000000000000000',
                DISCORD_WEBHOOK_URL: undefined,
                GAS_TANK_DO: {} as never,
                GAS_TANK_DB: {} as never,
                GAS_USAGE_KV: {} as never,
                GX: '0x0',
                GY: '0x0',
                JSON_RPC_API_KEY: 'json-rpc-key' as never,
                KNOT_APPLE_BUNDLE_ID: 'app.knot.ios',
                KNOT_APPLE_TEAM_ID: 'TEAM123456',
                KNOT_APP_ATTEST_ALLOW_DEVELOPMENT: 'true',
                KNOT_RP_ID: 'knot.fi',
                KNOT_RP_NAME: 'Knot',
                KNOT_RP_ORIGIN: 'https://knot.fi',
                MERKLE_VALIDATOR_MODULE: '0x0000000000000000000000000000000000000000',
                PINATA_GATEWAY_BASE_URL: 'https://gateway.pinata.cloud',
                PINATA_IMAGE_GROUP_ID: 'group',
                PINATA_JWT: 'jwt',
                RELAY_KV: {} as never,
                RELAY_QUEUE: {} as never,
                SERVER_KEY: 'server-key' as never,
                SPOKE_POOL: '0x0000000000000000000000000000000000000000',
                TREASURY_ADDRESS: '0x0000000000000000000000000000000000000000',
            } as unknown as CloudflareBindings,
            chain,
            options,
        );

        expect(client as unknown).toBe(sentinel);
    });
});

import { describe, expect, it } from 'bun:test';

import { createBundlerClient } from '../src/services/bundler';
import { CHAIN_REGISTRY } from '../src/constants/chains';
import type { CloudflareBindings, CreateAppOptions } from '../src/types';

describe('relay proxy bundler service', () => {
    it('returns the injected options.bundler client when present', () => {
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
        const client = createBundlerClient(
            {
                ANOMALY_QUEUE: {} as never,
                AUTH_DB: {} as never,
                AUTH_KV: {} as never,
                BUNDLER_API_KEY: 'api-key',
                DISCORD_WEBHOOK_URL: undefined,
                JSON_RPC_API_KEY: 'json-rpc-key',
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
            } as CloudflareBindings,
            chain,
            options,
        );

        expect(client as unknown).toBe(sentinel);
    });
});

import { describe, expect, it } from 'bun:test';

import { createGasUsageStore } from '../src/stores/gas';
import { uint } from '../src/utils';

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

describe('relay proxy gas usage store', () => {
    it('persists mainnet usage buckets', async () => {
        const kv = createMockKV();
        const store = createGasUsageStore({
            GAS_USAGE_KV: kv as unknown as KVNamespace,
        });

        const result = await store.incrementUsage(
            '0x1111111111111111111111111111111111111111',
            8453,
            uint('0x2'),
            Date.UTC(2026, 3, 15),
        );

        expect(result.chains['8453']?.hex).toBe('0x2');
        expect(result.totalUsdc.hex).toBe('0x2');
        expect(kv.records.size).toBe(1);
    });

    it('does not persist testnet usage buckets', async () => {
        const kv = createMockKV();
        const store = createGasUsageStore({
            GAS_USAGE_KV: kv as unknown as KVNamespace,
        });

        const result = await store.incrementUsage(
            '0x1111111111111111111111111111111111111111',
            84532,
            uint('0x2'),
            Date.UTC(2026, 3, 15),
        );

        expect(result.chains['84532']?.hex).toBe('0x2');
        expect(result.totalUsdc.hex).toBe('0x2');
        expect(kv.records.size).toBe(0);
    });
});

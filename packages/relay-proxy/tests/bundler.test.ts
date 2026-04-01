import { describe, expect, it } from 'bun:test';

import { createBundlerClient } from '../src/services/bundler';
import { CHAIN_REGISTRY } from '../src/constants/chains';

describe('relay proxy bundler service', () => {
    it('passes bundler config through to the injected factory', () => {
        const chain = CHAIN_REGISTRY[84532];
        const calls: unknown[] = [];
        const sentinel = { ok: true };

        const client = createBundlerClient(
            {
                bundlerApiKey: 'api-key',
                chain,
                jsonRpcApiKey: 'json-rpc-key',
            },
            (config) => {
                calls.push(config);
                return sentinel as never;
            },
        );

        expect(client as unknown).toBe(sentinel);
        expect(calls).toEqual([
            {
                bundlerApiKey: 'api-key',
                chain,
                jsonRpcApiKey: 'json-rpc-key',
            },
        ]);
    });
});

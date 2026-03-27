import { describe, expect, it, vi, beforeEach, type Mock } from 'vitest';
import { encodeFunctionData, type Address, type Hex } from 'viem';

import { storeDeferredTransaction } from '../repositories/deferred.repo';
import { EXECUTE_INTENT_ABI } from '../../shared/abis/accumulator';
import { DEFERRED_TX_TTL_SECONDS } from '../../shared/constants';
import {
    createMockEnv,
    createMockKV,
    createMockDONamespace,
    createMockDOStub,
} from '../../__tests__/mocks';
import type { Env } from '../../shared/types';
import type { RelayTxEnvelopeModel } from '../types';

describe('storeDeferredTransaction', () => {
    let env: Env;
    let kv: KVNamespace;
    let doStub: ReturnType<typeof createMockDOStub>;

    const ACCOUNT = '0x9999999999999999999999999999999999999999';
    const ACCUMULATOR: Address = '0x1111111111111111111111111111111111111111';
    const OWNER: Address = '0x9999999999999999999999999999999999999999';

    const calldata = encodeFunctionData({
        abi: EXECUTE_INTENT_ABI,
        functionName: 'executeIntent',
        args: [
            {
                salt: '0x2222222222222222222222222222222222222222222222222222222222222222' as const,
                fillDeadline: 1234567890,
                sumOutput: 1000000n,
                outputToken: '0x3333333333333333333333333333333333333333' as const,
                finalMinOutput: 500000n,
                finalOutputToken: '0x4444444444444444444444444444444444444444' as const,
                recipient: '0x5555555555555555555555555555555555555555' as const,
                destinationCaller: '0x6666666666666666666666666666666666666666' as const,
                destCalls: [],
            },
            [],
            '0x',
        ],
    });

    const tx: RelayTxEnvelopeModel = {
        chainId: 11155111,
        request: {
            from: OWNER,
            to: ACCUMULATOR,
            data: calldata as Hex,
        },
    };

    beforeEach(() => {
        kv = createMockKV();
        doStub = createMockDOStub();
        env = createMockEnv({
            DEFERRED_RELAY_KV: kv,
            WEBHOOK_TRACKER: createMockDONamespace(doStub),
        });
    });

    it('returns fillId as deferred ID', async () => {
        const id = await storeDeferredTransaction(ACCOUNT, 'testnet', tx, env);

        expect(id).toMatch(/^deferred-0x[a-f0-9]{64}$/);
    });

    it('stores payload in KV with correct TTL', async () => {
        await storeDeferredTransaction(ACCOUNT, 'testnet', tx, env);

        expect(kv.put).toHaveBeenCalledWith(
            expect.stringContaining('deferred-relay:testnet:'),
            expect.any(String),
            { expirationTtl: DEFERRED_TX_TTL_SECONDS },
        );
    });

    it('stores correct payload shape', async () => {
        await storeDeferredTransaction(ACCOUNT, 'testnet', tx, env);

        const putCall = (kv.put as Mock).mock.calls[0];
        const payload = JSON.parse(putCall[1]);

        expect(payload.account).toBe(ACCOUNT);
        expect(payload.supportMode).toBe('testnet');
        expect(payload.chainId).toBe(11155111);
        expect(payload.fillId).toMatch(/^0x/);
        expect(payload.createdAt).toBeDefined();
        expect(payload.gelatoId).toBeUndefined();
    });

    it('increments the webhook tracker DO', async () => {
        await storeDeferredTransaction(ACCOUNT, 'testnet', tx, env);

        expect(doStub.fetch).toHaveBeenCalledWith(
            expect.objectContaining({
                method: 'POST',
                url: 'https://do/increment',
            }),
        );
    });

    it('KV key contains supportMode and fillId', async () => {
        await storeDeferredTransaction(ACCOUNT, 'mainnet', tx, env);

        const putCall = (kv.put as Mock).mock.calls[0];
        const key: string = putCall[0];

        const parts = key.split(':');
        expect(parts[0]).toBe('deferred-relay');
        expect(parts[1]).toBe('mainnet');
        expect(parts[2]).toMatch(/^0x/); // fillId
    });

    it('generates deterministic IDs for same input', async () => {
        const id1 = await storeDeferredTransaction(ACCOUNT, 'testnet', tx, env);
        const id2 = await storeDeferredTransaction(ACCOUNT, 'testnet', tx, env);

        expect(id1).toBe(id2);
    });
});

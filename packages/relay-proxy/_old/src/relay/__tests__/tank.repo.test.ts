import { describe, expect, it, beforeEach, type Mock } from 'vitest';

import { readTankState, resolveFloorWei, writeTankState } from '../repositories/tank.repo';
import { createMockEnv, createMockKV } from '../../__tests__/mocks';
import type { Env } from '../../shared/types';

describe('tank.repo', () => {
    let env: Env;
    let kv: KVNamespace;

    beforeEach(() => {
        kv = createMockKV();
        env = createMockEnv({
            GAS_TANK_KV: kv,
            INITIAL_CREDIT_NATIVE: '0.01',
        });
    });

    const ACCOUNT = '0x1111111111111111111111111111111111111111';

    // -----------------------------------------------------------------------
    // readTankState
    // -----------------------------------------------------------------------

    describe('readTankState', () => {
        it('returns initial credit for unknown account', async () => {
            const state = await readTankState(env, ACCOUNT, 'testnet');

            expect(state.initialized).toBe(false);
            expect(state.balanceWei).toBe(10_000_000_000_000_000n); // 0.01 ETH
        });

        it('returns persisted balance for known account', async () => {
            const key = `gas-tank:testnet:${ACCOUNT.toLowerCase()}`;
            await kv.put(key, JSON.stringify({ balanceWei: '5000000000000000000' }));

            const state = await readTankState(env, ACCOUNT, 'testnet');

            expect(state.initialized).toBe(true);
            expect(state.balanceWei).toBe(5_000_000_000_000_000_000n);
        });

        it('returns initial credit for corrupted KV entry', async () => {
            const key = `gas-tank:testnet:${ACCOUNT.toLowerCase()}`;
            await kv.put(key, 'not-json');

            const state = await readTankState(env, ACCOUNT, 'testnet');

            expect(state.initialized).toBe(false);
        });

        it('returns initial credit when balanceWei field is missing', async () => {
            const key = `gas-tank:testnet:${ACCOUNT.toLowerCase()}`;
            await kv.put(key, JSON.stringify({ something: 'else' }));

            const state = await readTankState(env, ACCOUNT, 'testnet');

            expect(state.initialized).toBe(false);
        });
    });

    // -----------------------------------------------------------------------
    // writeTankState
    // -----------------------------------------------------------------------

    describe('writeTankState', () => {
        it('persists balance to KV', async () => {
            await writeTankState(env, ACCOUNT, 'mainnet', 2_000_000_000_000_000_000n);

            const key = `gas-tank:mainnet:${ACCOUNT.toLowerCase()}`;
            expect(kv.put).toHaveBeenCalledWith(
                key,
                expect.stringContaining('"balanceWei":"2000000000000000000"'),
            );
        });

        it('includes formatted native token balance', async () => {
            await writeTankState(env, ACCOUNT, 'testnet', 500_000_000_000_000_000n);

            const putCall = (kv.put as Mock).mock.calls[0];
            const payload = JSON.parse(putCall[1]);
            expect(payload.balanceNative).toBe('0.5');
        });

        it('includes updatedAt timestamp', async () => {
            await writeTankState(env, ACCOUNT, 'testnet', 0n);

            const putCall = (kv.put as Mock).mock.calls[0];
            const payload = JSON.parse(putCall[1]);
            expect(payload.updatedAt).toBeDefined();
            expect(new Date(payload.updatedAt).getTime()).not.toBeNaN();
        });
    });

    // -----------------------------------------------------------------------
    // resolveFloorWei
    // -----------------------------------------------------------------------

    describe('resolveFloorWei', () => {
        it('returns configured floor for testnet', () => {
            const envWithFloor = createMockEnv({
                FLOOR_TESTNET_NATIVE: '-10',
            });
            const floor = resolveFloorWei('testnet', envWithFloor);
            expect(floor).toBe(-10_000_000_000_000_000_000n);
        });

        it('returns configured floor for mainnet', () => {
            const envWithFloor = createMockEnv({
                FLOOR_MAINNET_NATIVE: '-2',
            });
            const floor = resolveFloorWei('mainnet', envWithFloor);
            expect(floor).toBe(-2_000_000_000_000_000_000n);
        });

        it('returns default when env var not set', () => {
            const envNoFloor = createMockEnv();
            const floor = resolveFloorWei('testnet', envNoFloor);
            // Default is -0.01 ETH
            expect(floor).toBe(-10_000_000_000_000_000n);
        });
    });
});

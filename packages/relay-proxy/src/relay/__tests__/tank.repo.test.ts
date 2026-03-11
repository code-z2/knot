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
            const state = await readTankState(env, ACCOUNT, 'LIMITED_TESTNET');

            expect(state.initialized).toBe(false);
            expect(state.balanceWei).toBe(10_000_000_000_000_000n); // 0.01 ETH
        });

        it('returns persisted balance for known account', async () => {
            const key = `gas-tank:LIMITED_TESTNET:${ACCOUNT.toLowerCase()}`;
            await kv.put(key, JSON.stringify({ balanceWei: '5000000000000000000' }));

            const state = await readTankState(env, ACCOUNT, 'LIMITED_TESTNET');

            expect(state.initialized).toBe(true);
            expect(state.balanceWei).toBe(5_000_000_000_000_000_000n);
        });

        it('returns initial credit for corrupted KV entry', async () => {
            const key = `gas-tank:LIMITED_TESTNET:${ACCOUNT.toLowerCase()}`;
            await kv.put(key, 'not-json');

            const state = await readTankState(env, ACCOUNT, 'LIMITED_TESTNET');

            expect(state.initialized).toBe(false);
        });

        it('returns initial credit when balanceWei field is missing', async () => {
            const key = `gas-tank:LIMITED_TESTNET:${ACCOUNT.toLowerCase()}`;
            await kv.put(key, JSON.stringify({ something: 'else' }));

            const state = await readTankState(env, ACCOUNT, 'LIMITED_TESTNET');

            expect(state.initialized).toBe(false);
        });
    });

    // -----------------------------------------------------------------------
    // writeTankState
    // -----------------------------------------------------------------------

    describe('writeTankState', () => {
        it('persists balance to KV', async () => {
            await writeTankState(env, ACCOUNT, 'LIMITED_MAINNET', 2_000_000_000_000_000_000n);

            const key = `gas-tank:LIMITED_MAINNET:${ACCOUNT.toLowerCase()}`;
            expect(kv.put).toHaveBeenCalledWith(
                key,
                expect.stringContaining('"balanceWei":"2000000000000000000"'),
            );
        });

        it('includes formatted native token balance', async () => {
            await writeTankState(env, ACCOUNT, 'LIMITED_TESTNET', 500_000_000_000_000_000n);

            const putCall = (kv.put as Mock).mock.calls[0];
            const payload = JSON.parse(putCall[1]);
            expect(payload.balanceNative).toBe('0.5');
        });

        it('includes updatedAt timestamp', async () => {
            await writeTankState(env, ACCOUNT, 'LIMITED_TESTNET', 0n);

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
        it('returns configured floor for LIMITED_TESTNET', () => {
            const envWithFloor = createMockEnv({
                FLOOR_LIMITED_TESTNET_NATIVE: '-10',
            });
            const floor = resolveFloorWei('LIMITED_TESTNET', envWithFloor);
            expect(floor).toBe(-10_000_000_000_000_000_000n);
        });

        it('returns configured floor for LIMITED_MAINNET', () => {
            const envWithFloor = createMockEnv({
                FLOOR_LIMITED_MAINNET_NATIVE: '-2',
            });
            const floor = resolveFloorWei('LIMITED_MAINNET', envWithFloor);
            expect(floor).toBe(-2_000_000_000_000_000_000n);
        });

        it('returns configured floor for FULL_MAINNET', () => {
            const envWithFloor = createMockEnv({ FLOOR_FULL_MAINNET_NATIVE: '0' });
            const floor = resolveFloorWei('FULL_MAINNET', envWithFloor);
            expect(floor).toBe(0n);
        });

        it('returns default when env var not set', () => {
            const envNoFloor = createMockEnv();
            const floor = resolveFloorWei('LIMITED_TESTNET', envNoFloor);
            // Default is -0.01 ETH
            expect(floor).toBe(-10_000_000_000_000_000n);
        });
    });
});

import { formatNativeToken, parseUsdToWei } from '../../shared/validation';

import type { Env, SupportMode } from '../../shared/types';
import type { TankStateModel } from '../types';

/** Reads the current gas tank balance for an account from KV. */
export async function readTankState(
    env: Env,
    account: string,
    supportMode: SupportMode,
): Promise<TankStateModel> {
    const key = buildTankKey(account, supportMode);
    const raw = await env.GAS_TANK_KV.get(key);

    const initial = parseUsdToWei(env.INITIAL_CREDIT_NATIVE ?? '0.01');

    if (!raw) {
        return { balanceWei: initial, initialized: false };
    }

    try {
        const payload = JSON.parse(raw) as { balanceWei?: string };
        if (!payload.balanceWei) throw new Error('missing balanceWei');
        return { balanceWei: BigInt(payload.balanceWei), initialized: true };
    } catch {
        return { balanceWei: initial, initialized: false };
    }
}

/** Persists an updated gas tank balance for an account to KV. */
export async function writeTankState(
    env: Env,
    account: string,
    supportMode: SupportMode,
    balanceWei: bigint,
): Promise<void> {
    const key = buildTankKey(account, supportMode);
    await env.GAS_TANK_KV.put(
        key,
        JSON.stringify({
            balanceWei: balanceWei.toString(),
            balanceNative: formatNativeToken(balanceWei),
            updatedAt: new Date().toISOString(),
        }),
    );
}

/** Resolves the minimum required gas tank balance before a transaction is rejected. */
export function resolveFloorWei(mode: SupportMode, env: Env): bigint {
    switch (mode) {
        case 'LIMITED_TESTNET':
            return parseUsdToWei(env.FLOOR_LIMITED_TESTNET_NATIVE ?? '-0.01');
        case 'LIMITED_MAINNET':
            return parseUsdToWei(env.FLOOR_LIMITED_MAINNET_NATIVE ?? '-0.01');
        case 'FULL_MAINNET':
            return parseUsdToWei(env.FLOOR_FULL_MAINNET_NATIVE ?? '0');
    }
}

function buildTankKey(account: string, supportMode: SupportMode): string {
    return `gas-tank:${supportMode}:${account.toLowerCase()}`;
}

import { DEFERRED_TX_TTL_SECONDS } from "../constants";
import { formatNativeToken, parseUsdToWei } from "../utils";

import type { Env, RelayTxEnvelopeModel, SupportMode, TankStateModel } from "./models";

export async function readTankState(
  env: Env,
  account: string,
  supportMode: SupportMode
): Promise<TankStateModel> {
  const key = buildTankKey(account, supportMode);
  const raw = await env.GAS_TANK_KV.get(key);
  
  const initial = parseUsdToWei(env.INITIAL_CREDIT_NATIVE ?? "0.01");
  
  if (!raw) {
    return { balanceWei: initial, initialized: false };
  }

  try {
    const payload = JSON.parse(raw) as { balanceWei?: string };
    if (!payload.balanceWei) {
      throw new Error("missing balanceWei");
    }
    return { balanceWei: BigInt(payload.balanceWei), initialized: true };
  } catch {
    return { balanceWei: initial, initialized: false };
  }
}

export async function writeTankState(
  env: Env,
  account: string,
  supportMode: SupportMode,
  balanceWei: bigint
): Promise<void> {
  const key = buildTankKey(account, supportMode);
  await env.GAS_TANK_KV.put(
    key,
    JSON.stringify({
      balanceWei: balanceWei.toString(),
      balanceNative: formatNativeToken(balanceWei),
      updatedAt: new Date().toISOString(),
    })
  );
}

export async function storeDeferredTransaction(
  account: string,
  supportMode: SupportMode,
  tx: RelayTxEnvelopeModel,
  env: Env
): Promise<string> {
  const id = `deferred-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const key = `deferred-relay:${supportMode}:${account}:${id}`;
  const payload = {
    id,
    account,
    supportMode,
    chainId: tx.chainId,
    request: tx.request,
    createdAt: new Date().toISOString(),
  };
  await env.GAS_TANK_KV.put(key, JSON.stringify(payload), { expirationTtl: DEFERRED_TX_TTL_SECONDS });
  return id;
}

export function resolveFloorWei(mode: SupportMode, env: Env): bigint {
  switch (mode) {
    case "LIMITED_TESTNET":
      return parseUsdToWei(env.FLOOR_LIMITED_TESTNET_NATIVE ?? "-0.01");
    case "LIMITED_MAINNET":
      return parseUsdToWei(env.FLOOR_LIMITED_MAINNET_NATIVE ?? "-0.01");
    case "FULL_MAINNET":
      return parseUsdToWei(env.FLOOR_FULL_MAINNET_NATIVE ?? "0");
  }
}

function buildTankKey(account: string, supportMode: SupportMode): string {
  return `gas-tank:${supportMode}:${account.toLowerCase()}`;
}

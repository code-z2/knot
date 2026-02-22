import {
  FAUCET_FUNDED_TTL_SECONDS,
  FAUCET_PENDING_TTL_SECONDS,
  SUPPORT_MODES,
} from "../constants";
import { BadRequestError } from "../errors";
import type { Env, FaucetFundRequestModel, SupportMode } from "../relay/models";
import { jsonResponse, normalizeAddress } from "../utils";

export async function handleFaucetFund(rawBody: string, env: Env, ctx: ExecutionContext): Promise<Response> {
  const request = parseFaucetFundRequest(rawBody);

  if (request.supportMode !== "LIMITED_TESTNET") {
    return jsonResponse({ ok: true, status: "skipped_non_testnet", supportMode: request.supportMode }, 200);
  }

  const faucetKV = resolveFaucetFundingKV(env);
  const fundingKey = buildFaucetFundingKey(request.eoaAddress, request.supportMode);
  const existing = await readFaucetFundingState(faucetKV, fundingKey);

  if (existing === "funded") {
    return jsonResponse({ ok: true, status: "already_funded" }, 200);
  }
  if (existing === "pending") {
    return jsonResponse({ ok: true, status: "funding_pending" }, 202);
  }

  await faucetKV.put(
    fundingKey,
    JSON.stringify({ state: "pending", updatedAt: Date.now() }),
    { expirationTtl: FAUCET_PENDING_TTL_SECONDS }
  );

  ctx.waitUntil(
    (async () => {
      try {
        if (!env.FAUCET_TRACKER_DO) {
          throw new Error("FAUCET_TRACKER_DO binding is not configured.");
        }

        const id = env.FAUCET_TRACKER_DO.idFromName("global-faucet");
        const stub = env.FAUCET_TRACKER_DO.get(id);

        const doRequest = new Request("http://do/fund", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ recipientAddress: request.eoaAddress })
        });

        const doRes = await stub.fetch(doRequest);
        
        if (!doRes.ok) {
          throw new Error(`Durable Object returned status: ${doRes.status}`);
        }

        await faucetKV.put(
          fundingKey,
          JSON.stringify({ state: "funded", updatedAt: Date.now() }),
          { expirationTtl: FAUCET_FUNDED_TTL_SECONDS }
        );
      } catch (error) {
        const reason = error instanceof Error ? error.message : "unknown faucet error";
        console.error("faucet funding failed", reason);
        await faucetKV.delete(fundingKey);
      }
    })()
  );

  return jsonResponse({ ok: true, status: "funding_initiated" }, 202);
}

function parseFaucetFundRequest(rawBody: string): FaucetFundRequestModel {
  let payload: unknown;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    throw new BadRequestError("Invalid JSON body.");
  }

  if (!payload || typeof payload !== "object") {
    throw new BadRequestError("Invalid faucet payload.");
  }

  const request = payload as Partial<FaucetFundRequestModel>;
  const eoaAddress = normalizeAddress(String(request.eoaAddress ?? ""));
  const supportMode = String(request.supportMode ?? "").trim();
  if (!SUPPORT_MODES.has(supportMode)) {
    throw new BadRequestError("Invalid supportMode.");
  }
  return { eoaAddress, supportMode: supportMode as SupportMode };
}

function resolveFaucetFundingKV(env: Env): KVNamespace {
  return env.FAUCET_FUNDING_KV ?? env.GAS_TANK_KV;
}

function buildFaucetFundingKey(eoaAddress: string, supportMode: SupportMode): string {
  return `faucet-funded:${supportMode}:${eoaAddress.toLowerCase()}`;
}

async function readFaucetFundingState(kv: KVNamespace, key: string): Promise<"pending" | "funded" | null> {
  const raw = await kv.get(key);
  if (!raw) {
    return null;
  }

  try {
    const parsed = JSON.parse(raw) as { state?: string };
    if (parsed.state === "pending") {
      return "pending";
    }
    if (parsed.state === "funded") {
      return "funded";
    }
  } catch {
    // Ignore malformed state and treat as not funded.
  }

  return null;
}

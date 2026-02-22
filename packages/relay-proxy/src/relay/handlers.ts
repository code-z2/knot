import { SUPPORT_MODES } from "../constants";
import { BadRequestError, PaymentRequiredError } from "../errors";
import { formatNativeToken, jsonResponse, normalizeAddress } from "../utils";

import {
  getRelayStatus,
  quoteTotalWei,
  sendRelayTransaction,
} from "./gelato";
import type { Env, RelaySubmissionModel, SupportMode } from "./models";
import { assertRelayTransactionsMatchAccount, parseSubmitRequest, sanitizePaymentOptions } from "./request";
import {
  readTankState,
  resolveFloorWei,
  storeDeferredTransaction,
  writeTankState,
} from "./tank";

export async function handleSubmitRelay(rawBody: string, env: Env): Promise<Response> {
  const body = parseSubmitRequest(rawBody);
  const account = body.account;
  const relayNowTxs = [...body.immediateTxs, ...body.backgroundTxs];
  const allTxs = [...relayNowTxs, ...body.deferredTxs];

  if (relayNowTxs.length === 0 && body.deferredTxs.length === 0) {
    throw new BadRequestError("At least one relay transaction is required.");
  }
  assertSingleSupportModeInvocation(allTxs, body.supportMode);
  await assertRelayTransactionsMatchAccount(account, allTxs);
  const estimatedDebitWei =
    relayNowTxs.length > 0 ? await quoteTotalWei(relayNowTxs, body.supportMode, env) : 0n;
  const minimumAllowedWei = resolveFloorWei(body.supportMode, env);

  const tankBefore = await readTankState(env, account, body.supportMode);
  const postDebitWei = tankBefore.balanceWei - estimatedDebitWei;

  if (postDebitWei < minimumAllowedWei) {
    const requiredTopUpWei = minimumAllowedWei - postDebitWei;
    const suggestedTopUpWei = requiredTopUpWei + estimatedDebitWei;
    throw new PaymentRequiredError({
      account,
      supportMode: body.supportMode,
      estimatedDebitWei,
      balanceWei: tankBefore.balanceWei,
      postDebitWei,
      minimumAllowedWei,
      requiredTopUpWei,
      suggestedTopUpWei,
      paymentOptions: sanitizePaymentOptions(body.paymentOptions ?? []),
    });
  }

  // Optimistic accounting: reserve/debit estimate first.
  await writeTankState(env, account, body.supportMode, postDebitWei);

  const immediateSubmissions: Array<RelaySubmissionModel & { chainId: number }> = [];
  const backgroundSubmissions: Array<RelaySubmissionModel & { chainId: number }> = [];
  const deferredSubmissions: Array<RelaySubmissionModel & { chainId: number }> = [];

  let hasError = false;
  let firstErrorMessage = "relay_submission_failed";

  const evaluateSettled = <T>(
    results: Array<PromiseSettledResult<T>>,
    targetSubmissions: Array<T>
  ) => {
    for (const result of results) {
      if (result.status === "fulfilled") {
        targetSubmissions.push(result.value);
      } else {
        hasError = true;
        firstErrorMessage =
          result.reason instanceof Error
            ? result.reason.message
            : String(result.reason);
      }
    }
  };

  const immediateResults = await Promise.allSettled(
    body.immediateTxs.map(async (tx) => {
      const result = await sendRelayTransaction("relayer_sendTransactionSync", tx, body.supportMode, env);
      return { chainId: tx.chainId, ...result };
    })
  );
  evaluateSettled(immediateResults, immediateSubmissions);

  const backgroundResults = await Promise.allSettled(
    body.backgroundTxs.map(async (tx) => {
      const result = await sendRelayTransaction("relayer_sendTransaction", tx, body.supportMode, env);
      return { chainId: tx.chainId, ...result };
    })
  );
  evaluateSettled(backgroundResults, backgroundSubmissions);

  const deferredResults = await Promise.allSettled(
    body.deferredTxs.map(async (tx) => {
      const supportMode = tx.supportMode ?? body.supportMode;
      const id = await storeDeferredTransaction(account, supportMode, tx, env);
      return { chainId: tx.chainId, id };
    })
  );
  evaluateSettled(deferredResults, deferredSubmissions);

  if (hasError) {
    // Keep debit as-is for now: we still pay infra for attempted relays.
    return jsonResponse(
      {
        ok: false,
        error: "relay_submission_failed",
        reason: firstErrorMessage,
        accounting: {
          supportMode: body.supportMode,
          estimatedDebitNative: formatNativeToken(estimatedDebitWei),
          balanceBeforeNative: formatNativeToken(tankBefore.balanceWei),
          balanceAfterNative: formatNativeToken(postDebitWei),
        },
        immediateSubmissions,
        backgroundSubmissions,
        deferredSubmissions,
      },
      502
    );
  }

  return jsonResponse({
    ok: true,
    accounting: {
      supportMode: body.supportMode,
      estimatedDebitNative: formatNativeToken(estimatedDebitWei),
      balanceBeforeNative: formatNativeToken(tankBefore.balanceWei),
      balanceAfterNative: formatNativeToken(postDebitWei),
    },
    immediateSubmissions,
    backgroundSubmissions,
    deferredSubmissions,
  });
}

export async function handleRelayStatus(url: URL, env: Env): Promise<Response> {
  const id = (url.searchParams.get("id") ?? "").trim();
  const modeRaw = (url.searchParams.get("supportMode") ?? "").trim();
  if (!id) {
    throw new BadRequestError("Missing relay task id.");
  }
  if (!SUPPORT_MODES.has(modeRaw)) {
    throw new BadRequestError("Missing or invalid supportMode.");
  }

  const supportMode = modeRaw as SupportMode;
  const status = await getRelayStatus(id, supportMode, env);
  return jsonResponse({ ok: true, status });
}

export async function handleCredit(url: URL, env: Env): Promise<Response> {
  const account = normalizeAddress(url.searchParams.get("account") ?? "");
  const modeRaw = (url.searchParams.get("supportMode") ?? "").trim();
  if (!SUPPORT_MODES.has(modeRaw)) {
    throw new BadRequestError("Invalid supportMode.");
  }

  const supportMode = modeRaw as SupportMode;
  const state = await readTankState(env, account, supportMode);

  return jsonResponse({
    ok: true,
    account,
    supportMode,
    balanceNative: formatNativeToken(state.balanceWei),
    initialized: state.initialized,
  });
}

function assertSingleSupportModeInvocation(txs: ReadonlyArray<{ supportMode?: SupportMode }>, fallback: SupportMode): void {
  let invocationMode: SupportMode | null = null;
  for (const tx of txs) {
    const mode = tx.supportMode ?? fallback;
    if (invocationMode === null) {
      invocationMode = mode;
      continue;
    }
    if (invocationMode !== mode) {
      throw new BadRequestError("Mixed support modes in one relay invocation are not allowed.");
    }
  }
}

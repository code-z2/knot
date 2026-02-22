import {
  createGelatoEvmRelayerClient,
  type GelatoEvmRelayerClient,
  type SendTransactionParameters,
  type Status,
} from "@gelatocloud/gasless";
import type { Address } from "viem";

import { BadRequestError } from "../errors";
import { parsePositiveInt } from "../utils";

import { estimateRelayRequestGas } from "./gas-estimator";
import type {
  Env,
  RelayStatusModel,
  RelaySubmissionModel,
  RelayTxEnvelopeModel,
  SupportMode,
} from "./models";

type RelayMethod = "relayer_sendTransaction" | "relayer_sendTransactionSync";

const DEFAULT_SYNC_TIMEOUT_MS = 30_000;
export async function quoteTotalWei(
  txs: readonly RelayTxEnvelopeModel[],
  defaultSupportMode: SupportMode,
  env: Env,
): Promise<bigint> {
  let total = 0n;

  for (const tx of txs) {
    const supportMode = tx.supportMode ?? defaultSupportMode;
    const client = getClientForSupportMode(supportMode, env);
    const gas = await estimateRelayRequestGas(tx.chainId, tx.request);
    
    // Always request quote against the NATIVE zero token
    const quote = await client.getFeeQuote({
      chainId: tx.chainId,
      gas,
      token: "0x0000000000000000000000000000000000000000" as Address, 
    });
    total += quote.fee;
  }

  return total;
}

export async function sendRelayTransaction(
  method: RelayMethod,
  tx: RelayTxEnvelopeModel,
  defaultSupportMode: SupportMode,
  env: Env,
): Promise<RelaySubmissionModel> {
  const supportMode = tx.supportMode ?? defaultSupportMode;
  const client = getClientForSupportMode(supportMode, env);
  const payload = buildSendTransactionParameters(tx);
  const id = await client.sendTransaction(payload);

  if (method === "relayer_sendTransactionSync") {
    const timeout = parsePositiveInt(
      env.GELATO_SYNC_TIMEOUT_MS,
      DEFAULT_SYNC_TIMEOUT_MS,
    );
    const receipt = await client.waitForReceipt({ id }, { timeout });
    return { id, transactionHash: receipt.transactionHash };
  }

  return { id };
}

export async function getRelayStatus(
  id: string,
  supportMode: SupportMode,
  env: Env,
): Promise<RelayStatusModel> {
  const relayID = id.trim();
  if (!relayID) {
    throw new BadRequestError("Missing relay task id.");
  }

  try {
    const client = getClientForSupportMode(supportMode, env);
    return toRelayStatusModel(await client.getStatus({ id: relayID }));
  } catch (error) {
    if (error instanceof Error) {
      throw new BadRequestError(
        `Relayer status lookup failed: ${error.message}`,
      );
    }
    throw new BadRequestError("Relayer status lookup failed.");
  }
}

function buildSendTransactionParameters(
  tx: RelayTxEnvelopeModel,
): SendTransactionParameters {
  const parameters: SendTransactionParameters = {
    chainId: tx.chainId,
    to: tx.request.to,
    data: tx.request.data,
  };

  if (tx.request.authorizationList?.length) {
    parameters.authorizationList = [...tx.request.authorizationList];
  }

  if (tx.request.value && BigInt(tx.request.value) > 0n) {
    throw new BadRequestError(
      `Unsupported request.value for chain ${tx.chainId}; include value in execute call payload instead.`,
    );
  }

  return parameters;
}

function toRelayStatusModel(status: Status): RelayStatusModel {
  return {
    id: status.id,
    rawStatus: String(status.status),
    state: normalizeStatusCode(status.status),
    transactionHash: "hash" in status ? status.hash : undefined,
    blockNumber: extractBlockNumberHex(status),
    failureReason: "message" in status ? status.message : undefined,
  };
}

function extractBlockNumberHex(status: Status): string | undefined {
  if (!("receipt" in status) || !status.receipt) {
    return undefined;
  }

  if (hasBlockNumber(status.receipt)) {
    return `0x${status.receipt.blockNumber.toString(16)}`;
  }

  if (
    hasNestedReceipt(status.receipt) &&
    hasBlockNumber(status.receipt.receipt)
  ) {
    return `0x${status.receipt.receipt.blockNumber.toString(16)}`;
  }

  return undefined;
}

function hasBlockNumber(value: object): value is { blockNumber: bigint } {
  const candidate = value as { blockNumber?: bigint };
  return typeof candidate.blockNumber === "bigint";
}

function hasNestedReceipt(value: object): value is { receipt: object } {
  const candidate = value as { receipt?: object };
  return !!candidate.receipt && typeof candidate.receipt === "object";
}

function normalizeStatusCode(code: number): RelayStatusModel["state"] {
  switch (code) {
    case 100:
    case 110:
      return "pending";
    case 200:
      return "executed";
    case 400:
      return "failed";
    case 500:
      return "reverted";
    default:
      return "unknown";
  }
}

function getClientForSupportMode(
  supportMode: SupportMode,
  env: Env,
): GelatoEvmRelayerClient {
  switch (supportMode) {
    case "LIMITED_TESTNET":
      return createClient(getApiKey(true, env), true);
    case "LIMITED_MAINNET":
    case "FULL_MAINNET":
      return createClient(getApiKey(false, env), false);
    default:
      throw new BadRequestError("Invalid support mode.");
  }
}

function createClient(
  apiKey: string,
  testnet: boolean,
): GelatoEvmRelayerClient {
  return createGelatoEvmRelayerClient({ apiKey, testnet });
}

function getApiKey(isTestnet: boolean, env: Env): string {
  const apiKey =
    (isTestnet
      ? env.GELATO_TESTNET_API_KEY
      : env.GELATO_MAINNET_API_KEY
    )?.trim() ?? "";
  if (!apiKey) {
    throw new BadRequestError(
      isTestnet
        ? "Missing GELATO_TESTNET_API_KEY."
        : "Missing GELATO_MAINNET_API_KEY.",
    );
  }
  return apiKey;
}

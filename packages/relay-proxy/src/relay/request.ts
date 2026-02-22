import type { Address, Hex } from "viem";
import { recoverAuthorizationAddress } from "viem/utils";

import { SUPPORT_MODES } from "../constants";
import { BadRequestError } from "../errors";
import { normalizeAddress } from "../utils";

import type {
  PaymentOptionModel,
  RelayAuthorizationModel,
  RelayTransactionRequestModel,
  RelayTxEnvelopeModel,
  RelayYParity,
  SubmitRelayRequestModel,
  SupportMode,
} from "./models";

type JsonPrimitive = string | number | boolean | null;
type JsonValue = JsonPrimitive | JsonObject | JsonValue[];
type JsonObject = { [key: string]: JsonValue };

export function parseSubmitRequest(rawBody: string): SubmitRelayRequestModel {
  const payload = parseJsonObject(rawBody, "Invalid JSON body.", "Invalid relay request payload.");
  const account = parseAddress(payload.account, "Invalid account address.");
  const supportMode = parseSupportMode(payload.supportMode, "Invalid supportMode.");

  return {
    account,
    supportMode,
    immediateTxs: parseTxEnvelopeList(payload.immediateTxs, "immediateTxs"),
    backgroundTxs: parseTxEnvelopeList(payload.backgroundTxs, "backgroundTxs"),
    deferredTxs: parseTxEnvelopeList(payload.deferredTxs, "deferredTxs"),
    paymentOptions: parsePaymentOptions(payload.paymentOptions),
  };
}

export async function assertRelayTransactionsMatchAccount(
  account: string,
  txs: readonly RelayTxEnvelopeModel[]
): Promise<void> {
  for (const tx of txs) {
    if (tx.request.from !== account) {
      throw new BadRequestError(`Relay tx account mismatch for chain ${tx.chainId}.`);
    }

    for (const [index, auth] of (tx.request.authorizationList ?? []).entries()) {
      if (auth.chainId !== tx.chainId) {
        throw new BadRequestError(`request.authorizationList[${index}].chainId must match relay chain ${tx.chainId}.`);
      }

      const recoveredAuthority = await recoverAuthAddress(auth, index);
      if (recoveredAuthority !== account) {
        throw new BadRequestError(`request.authorizationList[${index}] signer mismatch for chain ${tx.chainId}.`);
      }
    }
  }
}

export function sanitizePaymentOptions(options: readonly PaymentOptionModel[]): PaymentOptionModel[] {
  return [...options];
}

async function recoverAuthAddress(auth: RelayAuthorizationModel, index: number): Promise<string> {
  try {
    return normalizeAddress(await recoverAuthorizationAddress({ authorization: auth }));
  } catch {
    throw new BadRequestError(`request.authorizationList[${index}] has an invalid EIP-7702 signature.`);
  }
}

function parseTxEnvelopeList(value: JsonValue | undefined, fieldName: string): RelayTxEnvelopeModel[] {
  if (!Array.isArray(value)) {
    throw new BadRequestError(`${fieldName} must be an array.`);
  }

  return value.map((item) => parseTxEnvelope(item, fieldName));
}

function parseTxEnvelope(value: JsonValue, fieldName: string): RelayTxEnvelopeModel {
  const item = asJsonObject(value, `Invalid relay tx envelope in ${fieldName}.`);
  const chainId = parsePositiveInteger(item.chainId, `Invalid chainId in ${fieldName}.`);
  const supportMode = parseOptionalSupportMode(item.supportMode, `Invalid supportMode in ${fieldName}.`);
  const request = parseTxRequest(item.request, chainId, fieldName);

  return { chainId, supportMode, request };
}

function parseTxRequest(value: JsonValue | undefined, chainId: number, fieldName: string): RelayTransactionRequestModel {
  const request = asJsonObject(value, `Missing request object in ${fieldName}.`);
  const out: RelayTransactionRequestModel = {
    from: parseAddress(request.from, `Invalid request.from for chain ${chainId}.`),
    to: parseAddress(request.to, `Invalid request.to for chain ${chainId}.`),
    data: parseHexData(request.data, `Invalid request.data for chain ${chainId}.`),
  };

  const valueHex = parseOptionalHexQuantity(request.value, `Invalid request.value for chain ${chainId}.`);
  if (valueHex) {
    out.value = valueHex;
  }

  const authorizationList = parseAuthorizationList(
    request.authorizationList,
    chainId,
    `Invalid request.authorizationList for chain ${chainId}.`
  );
  if (authorizationList.length > 0) {
    out.authorizationList = authorizationList;
  }

  return out;
}

function parseAuthorizationList(value: JsonValue | undefined, chainId: number, errorMessage: string): RelayAuthorizationModel[] {
  if (value === undefined) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw new BadRequestError(errorMessage);
  }

  return value.map((item, index) => {
    const auth = asJsonObject(item, `${errorMessage} Invalid item at index ${index}.`);
    return {
      address: parseAddress(auth.address, `Invalid request.authorizationList[${index}].address for chain ${chainId}.`),
      chainId: parsePositiveInteger(
        auth.chainId,
        `Invalid request.authorizationList[${index}].chainId for chain ${chainId}.`
      ),
      nonce: parseUnsignedInteger(auth.nonce, `Invalid request.authorizationList[${index}].nonce for chain ${chainId}.`),
      r: parseHexData(auth.r, `Invalid request.authorizationList[${index}].r for chain ${chainId}.`),
      s: parseHexData(auth.s, `Invalid request.authorizationList[${index}].s for chain ${chainId}.`),
      yParity: parseYParity(auth.yParity, `Invalid request.authorizationList[${index}].yParity for chain ${chainId}.`),
    };
  });
}

function parsePaymentOptions(value: JsonValue | undefined): PaymentOptionModel[] {
  if (value === undefined) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw new BadRequestError("paymentOptions must be an array.");
  }

  return value.map((item, index) => {
    const option = asJsonObject(item, `Invalid paymentOptions[${index}].`);
    return {
      chainId: parsePositiveInteger(option.chainId, `Invalid paymentOptions[${index}].chainId.`),
      tokenAddress: parseAddress(option.tokenAddress, `Invalid paymentOptions[${index}].tokenAddress.`),
      symbol: parseNonEmptyString(option.symbol, `Invalid paymentOptions[${index}].symbol.`),
      amount: parsePositiveDecimalString(option.amount, `Invalid paymentOptions[${index}].amount.`),
    };
  });
}

function parseJsonObject(rawBody: string, jsonError: string, payloadError: string): JsonObject {
  let parsed: JsonValue;
  try {
    parsed = JSON.parse(rawBody) as JsonValue;
  } catch {
    throw new BadRequestError(jsonError);
  }

  if (!isJsonObject(parsed)) {
    throw new BadRequestError(payloadError);
  }
  return parsed;
}

function isJsonObject(value: JsonValue): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asJsonObject(value: JsonValue | undefined, errorMessage: string): JsonObject {
  if (value === undefined || !isJsonObject(value)) {
    throw new BadRequestError(errorMessage);
  }
  return value;
}

function parseSupportMode(value: JsonValue | undefined, errorMessage: string): SupportMode {
  if (typeof value !== "string") {
    throw new BadRequestError(errorMessage);
  }
  const normalized = value.trim();
  if (!SUPPORT_MODES.has(normalized)) {
    throw new BadRequestError(errorMessage);
  }
  return normalized as SupportMode;
}

function parseOptionalSupportMode(value: JsonValue | undefined, errorMessage: string): SupportMode | undefined {
  if (value === undefined) {
    return undefined;
  }
  return parseSupportMode(value, errorMessage);
}

function parseAddress(value: JsonValue | undefined, errorMessage: string): Address {
  if (typeof value !== "string") {
    throw new BadRequestError(errorMessage);
  }
  return normalizeAddress(value) as Address;
}

function parseHexData(value: JsonValue | undefined, errorMessage: string): Hex {
  if (typeof value !== "string") {
    throw new BadRequestError(errorMessage);
  }
  const trimmed = value.trim();
  if (!/^0x[0-9a-fA-F]*$/.test(trimmed)) {
    throw new BadRequestError(errorMessage);
  }
  return trimmed as Hex;
}

function parseOptionalHexQuantity(value: JsonValue | undefined, errorMessage: string): Hex | undefined {
  if (value === undefined) {
    return undefined;
  }
  if (typeof value !== "string") {
    throw new BadRequestError(errorMessage);
  }
  const trimmed = value.trim().toLowerCase();
  if (!/^0x[0-9a-f]+$/.test(trimmed)) {
    throw new BadRequestError(errorMessage);
  }
  return trimmed as Hex;
}

function parsePositiveInteger(value: JsonValue | undefined, errorMessage: string): number {
  const out = parseUnsignedInteger(value, errorMessage);
  if (out <= 0) {
    throw new BadRequestError(errorMessage);
  }
  return out;
}

function parseUnsignedInteger(value: JsonValue | undefined, errorMessage: string): number {
  if (typeof value === "number") {
    if (Number.isSafeInteger(value) && value >= 0) {
      return value;
    }
    throw new BadRequestError(errorMessage);
  }

  if (typeof value === "string" && /^\d+$/.test(value.trim())) {
    const parsed = Number(value.trim());
    if (Number.isSafeInteger(parsed)) {
      return parsed;
    }
  }

  throw new BadRequestError(errorMessage);
}

function parseYParity(value: JsonValue | undefined, errorMessage: string): RelayYParity {
  const raw = parseUnsignedInteger(value, errorMessage);
  if (raw === 0 || raw === 1) {
    return raw;
  }
  if (raw === 27 || raw === 28) {
    return (raw - 27) as RelayYParity;
  }
  throw new BadRequestError(errorMessage);
}

function parseNonEmptyString(value: JsonValue | undefined, errorMessage: string): string {
  if (typeof value !== "string") {
    throw new BadRequestError(errorMessage);
  }
  const trimmed = value.trim();
  if (!trimmed) {
    throw new BadRequestError(errorMessage);
  }
  return trimmed;
}

function parsePositiveDecimalString(value: JsonValue | undefined, errorMessage: string): string {
  if (typeof value !== "string" && typeof value !== "number") {
    throw new BadRequestError(errorMessage);
  }
  const normalized = String(value).trim();
  const asNumber = Number(normalized);
  if (!Number.isFinite(asNumber) || asNumber <= 0) {
    throw new BadRequestError(errorMessage);
  }
  return normalized;
}

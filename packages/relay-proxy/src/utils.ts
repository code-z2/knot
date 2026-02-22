import { bytesToHex, getAddress, isAddress } from "viem";

import { JSON_HEADERS } from "./constants";
import { AuthError, BadRequestError } from "./errors";
import type { Env } from "./relay/models";

export function normalizeHostname(hostname: string): string {
  return hostname.trim().toLowerCase().replace(/\.+$/, "");
}

export function isRouteAllowedForHostname(hostname: string, method: string, path: string): boolean {
  const upperMethod = method.toUpperCase();

  if (hostname === "upload.knot.fi") {
    if (path === "/health") {
      return upperMethod === "GET" || upperMethod === "OPTIONS";
    }
    if (path === "/v1/images/direct-upload") {
      return upperMethod === "POST" || upperMethod === "OPTIONS";
    }
    return false;
  }

  if (hostname === "relay.knot.fi") {
    if (path === "/v1/images/direct-upload") {
      return false;
    }
    return true;
  }

  // Non-production hosts (workers.dev, localhost, etc.) keep full routing.
  return true;
}

export function resolveRequiredEnvValue(value: string | undefined, name: string): string {
  const trimmed = (value ?? "").trim();
  if (!trimmed) {
    throw new BadRequestError(`Missing required env var: ${name}`);
  }
  return trimmed;
}

export function sanitizeFileName(value: string): string {
  const normalized = value
    .trim()
    .replace(/[^a-zA-Z0-9._-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-+|-+$/g, "");
  return normalized.slice(0, 120);
}

export function randomHex(bytes: number): string {
  const value = new Uint8Array(bytes);
  crypto.getRandomValues(value);
  return Array.from(value)
    .map((item) => item.toString(16).padStart(2, "0"))
    .join("");
}

export function parseBigint(value: string): bigint {
  const normalized = value.trim().toLowerCase();
  if (!normalized) {
    return 0n;
  }
  if (normalized.startsWith("0x")) {
    return BigInt(normalized);
  }
  if (/^-?\d+$/.test(normalized)) {
    return BigInt(normalized);
  }
  throw new BadRequestError(`Cannot parse bigint value: ${value}`);
}

export function parseBoundedInteger(
  value: string,
  min: number,
  max: number,
  fallback: number
): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  const rounded = Math.floor(parsed);
  if (rounded < min || rounded > max) {
    return fallback;
  }
  return rounded;
}

export function parsePositiveInt(value: string | undefined, fallback: number): number {
  if (!value) {
    return fallback;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return Math.floor(parsed);
}

export function normalizeAddress(value: string): string {
  const normalized = value.trim().toLowerCase();
  if (!isAddress(normalized)) {
    throw new BadRequestError("Invalid account address.");
  }
  return getAddress(normalized).toLowerCase();
}

import { formatEther, parseEther } from "viem";

export function formatNativeToken(wei: bigint): string {
  const etherString = formatEther(wei);
  return etherString.replace(/\.?0+$/, "");
}

export function parseUsdToWei(value: string): bigint {
  const trimmed = value.trim();
  if (!trimmed) {
    return 0n;
  }
  
  if (trimmed.startsWith("-")) {
    const positivePart = trimmed.slice(1);
    try {
      return -parseEther(positivePart);
    } catch {
      return 0n;
    }
  }

  try {
    return parseEther(trimmed);
  } catch {
    return 0n;
  }
}



export function pickString(dict: Record<string, unknown>, keys: string[]): string | null {
  for (const key of keys) {
    const value = dict[key];
    if (typeof value === "string" && value.trim() !== "") {
      return value;
    }
    if (typeof value === "number" && Number.isFinite(value)) {
      return String(value);
    }
    if (value && typeof value === "object") {
      const nested = pickString(value as Record<string, unknown>, keys);
      if (nested) {
        return nested;
      }
    }
  }
  return null;
}

export async function authorizeRequest(request: Request, env: Env, rawBody: string): Promise<void> {
  const authHeader = (request.headers.get("Authorization") ?? "").trim();
  if (!authHeader.startsWith("Bearer ")) {
    throw new AuthError("Missing bearer token.");
  }

  const token = authHeader.slice("Bearer ".length).trim();
  if (!token || !timingSafeEqual(token, env.RELAY_AUTH_TOKEN.trim())) {
    throw new AuthError("Invalid bearer token.");
  }

  const secret = (env.RELAY_AUTH_HMAC_SECRET ?? "").trim();
  if (!secret) {
    return;
  }

  const timestamp = (request.headers.get("X-Relay-Timestamp") ?? "").trim();
  const signature = (request.headers.get("X-Relay-Signature") ?? "").trim().toLowerCase();
  if (!timestamp || !signature) {
    throw new AuthError("Missing relay signature headers.");
  }

  const parsedTimestamp = Number(timestamp);
  if (!Number.isFinite(parsedTimestamp)) {
    throw new AuthError("Invalid relay timestamp.");
  }

  const now = Math.floor(Date.now() / 1000);
  if (Math.abs(now - Math.floor(parsedTimestamp)) > 300) {
    throw new AuthError("Relay timestamp is outside allowed window.");
  }

  const expected = await hmacHex(secret, `${timestamp}.${rawBody}`);
  if (!timingSafeEqual(signature, expected)) {
    throw new AuthError("Invalid relay signature.");
  }
}

export function jsonResponse(payload: unknown, status = 200): Response {
  return corsResponse(
    new Response(JSON.stringify(payload), {
      status,
      headers: JSON_HEADERS,
    })
  );
}

export function corsResponse(response: Response): Response {
  response.headers.set("Access-Control-Allow-Origin", "*");
  response.headers.set("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  response.headers.set("Access-Control-Allow-Headers", "authorization,content-type,x-relay-timestamp,x-relay-signature");
  return response;
}

async function hmacHex(secret: string, payload: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const mac = await crypto.subtle.sign("HMAC", key, encoder.encode(payload));
  return bytesToHex(new Uint8Array(mac)).slice(2);
}

function timingSafeEqual(a: string, b: string): boolean {
  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);

  if (aBytes.length !== bBytes.length) {
    return false;
  }

  let diff = 0;
  for (let i = 0; i < aBytes.length; i += 1) {
    diff |= aBytes[i] ^ bBytes[i];
  }
  return diff === 0;
}

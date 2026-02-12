import {
  createPublicClient,
  createWalletClient,
  defineChain,
  encodeFunctionData,
  getAddress,
  http,
  isAddress,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

export interface Env {
  GAS_TANK_KV: KVNamespace;
  RELAY_AUTH_TOKEN: string;
  RELAY_AUTH_HMAC_SECRET?: string;
  GELATO_API_KEY: string;
  PINATA_JWT: string;
  PINATA_GATEWAY_BASE_URL: string;
  PINATA_GROUP_ID: string;
  PINATA_SIGN_EXPIRES_SECONDS?: string;
  PINATA_MAX_FILE_SIZE_BYTES?: string;
  GELATO_RPC_TEMPLATE?: string;
  INITIAL_CREDIT_USDC?: string;
  FLOOR_LIMITED_TESTNET_USDC?: string;
  FLOOR_LIMITED_MAINNET_USDC?: string;
  FLOOR_FULL_MAINNET_USDC?: string;
  USDC_DECIMALS?: string;
  FAUCET_PRIVATE_KEY?: string;
  FAUCET_RPC_SEPOLIA?: string;
  FAUCET_RPC_BASE_SEPOLIA?: string;
  FAUCET_RPC_ARB_SEPOLIA?: string;
}

type SupportMode = "LIMITED_TESTNET" | "LIMITED_MAINNET" | "FULL_MAINNET";

interface RelayTxEnvelope {
  chainId: number;
  request: Record<string, unknown>;
}

interface PaymentOption {
  chainId: number;
  tokenAddress: string;
  symbol: string;
  amount: string;
}

interface SubmitRelayRequest {
  account: string;
  supportMode: SupportMode;
  priorityTxs: RelayTxEnvelope[];
  txs: RelayTxEnvelope[];
  paymentOptions?: PaymentOption[];
}

interface RelaySubmission {
  id: string;
  transactionHash?: string;
}

interface RelayStatus {
  id: string;
  rawStatus: string;
  state: string;
  transactionHash?: string;
  blockNumber?: string;
  failureReason?: string;
}

interface TankState {
  balanceMicros: bigint;
  initialized: boolean;
}

interface DirectUploadRequest {
  eoaAddress: string;
  fileName: string;
  contentType: string;
}

interface NormalizedDirectUploadRequest {
  eoaAddress: string;
  fileName: string;
  contentType: string;
  imageID: string;
}

interface FaucetFundRequest {
  eoaAddress: string;
}

const SUPPORT_MODES: Set<string> = new Set(["LIMITED_TESTNET", "LIMITED_MAINNET", "FULL_MAINNET"]);
const ETH_DRIP_WEI = 10_000_000_000_000_000n; // 0.01 ETH
const USDC_DRIP_AMOUNT = 2_000_000n; // 2 USDC (6 decimals)
const INITIALIZE_SELECTOR = "0xc62f0714";

const TESTNET_USDC_BY_CHAIN: Record<number, Address> = {
  11155111: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238", // Sepolia
  84532: "0x036CbD53842c5426634e7929541eC2318f3dCF7e", // Base Sepolia
  421614: "0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d", // Arbitrum Sepolia
};

const ERC20_TRANSFER_ABI = [
  {
    type: "function",
    name: "transfer",
    stateMutability: "nonpayable",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    try {
      const url = new URL(request.url);
      const path = url.pathname;
      const hostname = normalizeHostname(url.hostname);

      if (!isRouteAllowedForHostname(hostname, request.method, path)) {
        return jsonResponse({ ok: false, error: "not_found" }, 404);
      }

      if (request.method === "OPTIONS") {
        return corsResponse(new Response(null, { status: 204 }));
      }

      if (request.method === "GET" && path === "/health") {
        return jsonResponse({ ok: true, service: "relay-proxy" });
      }

      if (request.method === "POST" && path === "/v1/relay/submit") {
        const rawBody = await request.text();
        await authorizeRequest(request, env, rawBody);
        return await handleSubmitRelay(rawBody, env);
      }

      if (request.method === "GET" && path === "/v1/relay/status") {
        await authorizeRequest(request, env, "");
        return await handleRelayStatus(url, env);
      }

      if (request.method === "GET" && path === "/v1/relay/credit") {
        await authorizeRequest(request, env, "");
        return await handleCredit(url, env);
      }

      if (request.method === "POST" && path === "/v1/images/direct-upload") {
        const rawBody = await request.text();
        await authorizeRequest(request, env, rawBody);
        return await handleDirectImageUpload(rawBody, env);
      }

      if (request.method === "POST" && path === "/v1/faucet/fund") {
        const rawBody = await request.text();
        await authorizeRequest(request, env, rawBody);
        return await handleFaucetFund(rawBody, env, ctx);
      }

      return jsonResponse({ ok: false, error: "not_found" }, 404);
    } catch (error) {
      if (error instanceof AuthError) {
        return jsonResponse({ ok: false, error: "unauthorized", reason: error.message }, 401);
      }
      if (error instanceof BadRequestError) {
        return jsonResponse({ ok: false, error: "bad_request", reason: error.message }, 400);
      }
      if (error instanceof PaymentRequiredError) {
        return jsonResponse(
          {
            ok: false,
            error: "payment_required",
            account: error.account,
            supportMode: error.supportMode,
            estimatedDebitUsdc: formatUsd(error.estimatedDebitMicros, error.usdcDecimals),
            balanceUsdc: formatUsd(error.balanceMicros, error.usdcDecimals),
            postDebitUsdc: formatUsd(error.postDebitMicros, error.usdcDecimals),
            minimumAllowedUsdc: formatUsd(error.minimumAllowedMicros, error.usdcDecimals),
            requiredTopUpUsdc: formatUsd(error.requiredTopUpMicros, error.usdcDecimals),
            suggestedTopUpUsdc: formatUsd(error.suggestedTopUpMicros, error.usdcDecimals),
            paymentOptions: error.paymentOptions,
          },
          402
        );
      }

      const reason = error instanceof Error ? error.message : "internal_error";
      return jsonResponse({ ok: false, error: "internal_error", reason }, 500);
    }
  },
};

function normalizeHostname(hostname: string): string {
  return hostname.trim().toLowerCase().replace(/\.+$/, "");
}

function isRouteAllowedForHostname(hostname: string, method: string, path: string): boolean {
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

async function handleSubmitRelay(rawBody: string, env: Env): Promise<Response> {
  const body = parseSubmitRequest(rawBody);
  const account = normalizeAddress(body.account);
  const usdcDecimals = resolveUsdcDecimals(env);
  const allTxs = [...body.priorityTxs, ...body.txs];

  if (allTxs.length === 0) {
    throw new BadRequestError("At least one relay transaction is required.");
  }
  assertRelayTransactionsMatchAccount(account, allTxs);
  const freeInitializationTxIndexes = await resolveFreeInitializationTransactionIndexes(
    account,
    allTxs,
    env
  );
  const billableTxs = allTxs.filter((_, index) => !freeInitializationTxIndexes.has(index));

  const estimatedDebitMicros =
    billableTxs.length > 0
      ? await quoteTotalMicros(billableTxs, env)
      : 0n;
  const minimumAllowedMicros = resolveFloorMicros(body.supportMode, env, usdcDecimals);

  const tankBefore = await readTankState(env, account, body.supportMode, usdcDecimals);
  const postDebitMicros = tankBefore.balanceMicros - estimatedDebitMicros;

  if (postDebitMicros < minimumAllowedMicros) {
    const requiredTopUpMicros = minimumAllowedMicros - postDebitMicros;
    const suggestedTopUpMicros = requiredTopUpMicros + estimatedDebitMicros;
    throw new PaymentRequiredError({
      account,
      supportMode: body.supportMode,
      estimatedDebitMicros,
      balanceMicros: tankBefore.balanceMicros,
      postDebitMicros,
      minimumAllowedMicros,
      requiredTopUpMicros,
      suggestedTopUpMicros,
      usdcDecimals,
      paymentOptions: sanitizePaymentOptions(body.paymentOptions ?? []),
    });
  }

  // Optimistic accounting: reserve/debit estimate first.
  await writeTankState(env, account, body.supportMode, postDebitMicros, usdcDecimals);

  const prioritySubmissions: Array<RelaySubmission & { chainId: number }> = [];
  const submissions: Array<RelaySubmission & { chainId: number }> = [];

  try {
    for (const tx of body.priorityTxs) {
      const result = await sendRelayTransaction("relayer_sendTransactionSync", tx, env);
      prioritySubmissions.push({ chainId: tx.chainId, ...result });
    }

    for (const tx of body.txs) {
      const result = await sendRelayTransaction("relayer_sendTransaction", tx, env);
      submissions.push({ chainId: tx.chainId, ...result });
    }
  } catch (error) {
    // Keep debit as-is for now: we still pay infra for attempted relays.
    const reason = error instanceof Error ? error.message : "relay_submission_failed";
    return jsonResponse(
      {
        ok: false,
        error: "relay_submission_failed",
        reason,
        accounting: {
          supportMode: body.supportMode,
          estimatedDebitUsdc: formatUsd(estimatedDebitMicros, usdcDecimals),
          balanceBeforeUsdc: formatUsd(tankBefore.balanceMicros, usdcDecimals),
          balanceAfterUsdc: formatUsd(postDebitMicros, usdcDecimals),
        },
        prioritySubmissions,
        submissions,
      },
      502
    );
  }

  return jsonResponse({
    ok: true,
    accounting: {
      supportMode: body.supportMode,
      estimatedDebitUsdc: formatUsd(estimatedDebitMicros, usdcDecimals),
      balanceBeforeUsdc: formatUsd(tankBefore.balanceMicros, usdcDecimals),
      balanceAfterUsdc: formatUsd(postDebitMicros, usdcDecimals),
    },
    prioritySubmissions,
    submissions,
  });
}

async function handleRelayStatus(url: URL, env: Env): Promise<Response> {
  const chainId = parseInteger(url.searchParams.get("chainId"), "chainId");
  const id = (url.searchParams.get("id") ?? "").trim();
  if (!id) {
    throw new BadRequestError("Missing relay task id.");
  }

  const raw = await sendGelatoRpc(chainId, "relayer_getStatus", [id], env);
  const status = parseRelayStatus(raw, id);
  return jsonResponse({ ok: true, chainId, status });
}

async function handleCredit(url: URL, env: Env): Promise<Response> {
  const account = normalizeAddress(url.searchParams.get("account") ?? "");
  const modeRaw = (url.searchParams.get("supportMode") ?? "").trim();
  if (!SUPPORT_MODES.has(modeRaw)) {
    throw new BadRequestError("Invalid supportMode.");
  }

  const supportMode = modeRaw as SupportMode;
  const usdcDecimals = resolveUsdcDecimals(env);
  const state = await readTankState(env, account, supportMode, usdcDecimals);

  return jsonResponse({
    ok: true,
    account,
    supportMode,
    balanceUsdc: formatUsd(state.balanceMicros, usdcDecimals),
    initialized: state.initialized,
  });
}

async function handleDirectImageUpload(rawBody: string, env: Env): Promise<Response> {
  const body = parseDirectUploadRequest(rawBody);
  const uploadURL = await createPinataSignedUploadURL(body, env);
  const gatewayBaseURL = resolvePinataGatewayBaseURL(env);

  return jsonResponse({
    ok: true,
    uploadURL,
    imageID: body.imageID,
    gatewayBaseURL,
  });
}

async function handleFaucetFund(rawBody: string, env: Env, ctx: ExecutionContext): Promise<Response> {
  const request = parseFaucetFundRequest(rawBody);
  const rpcByChain = resolveFaucetRPCByChain(env);
  normalizePrivateKey(env.FAUCET_PRIVATE_KEY ?? "");

  ctx.waitUntil(
    fundAccount(request.eoaAddress, env, rpcByChain).catch((error) => {
      const reason = error instanceof Error ? error.message : "unknown faucet error";
      console.error("faucet funding failed", reason);
    })
  );

  return jsonResponse({ ok: true, status: "funding_initiated" }, 202);
}

function parseSubmitRequest(rawBody: string): SubmitRelayRequest {
  let payload: unknown;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    throw new BadRequestError("Invalid JSON body.");
  }

  if (!payload || typeof payload !== "object") {
    throw new BadRequestError("Invalid relay request payload.");
  }

  const maybe = payload as Partial<SubmitRelayRequest>;
  const account = normalizeAddress(maybe.account ?? "");

  const supportMode = String(maybe.supportMode ?? "").trim();
  if (!SUPPORT_MODES.has(supportMode)) {
    throw new BadRequestError("Invalid supportMode.");
  }

  const priorityTxs = normalizeTxEnvelopes(maybe.priorityTxs ?? []);
  const txs = normalizeTxEnvelopes(maybe.txs ?? []);

  return {
    account,
    supportMode: supportMode as SupportMode,
    priorityTxs,
    txs,
    paymentOptions: Array.isArray(maybe.paymentOptions) ? maybe.paymentOptions : [],
  };
}

function parseFaucetFundRequest(rawBody: string): FaucetFundRequest {
  let payload: unknown;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    throw new BadRequestError("Invalid JSON body.");
  }

  if (!payload || typeof payload !== "object") {
    throw new BadRequestError("Invalid faucet payload.");
  }

  const request = payload as Partial<FaucetFundRequest>;
  const eoaAddress = normalizeAddress(String(request.eoaAddress ?? ""));
  return { eoaAddress };
}

function parseDirectUploadRequest(rawBody: string): NormalizedDirectUploadRequest {
  let payload: unknown;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    throw new BadRequestError("Invalid JSON body.");
  }

  if (!payload || typeof payload !== "object") {
    throw new BadRequestError("Invalid direct upload payload.");
  }

  const request = payload as Partial<DirectUploadRequest>;
  const eoaAddress = normalizeAddress(String(request.eoaAddress ?? ""));
  const fileName = sanitizeFileName(String(request.fileName ?? ""));
  if (!fileName) {
    throw new BadRequestError("Invalid fileName.");
  }

  const contentType = String(request.contentType ?? "").trim().toLowerCase();
  if (!contentType.startsWith("image/")) {
    throw new BadRequestError("Only image uploads are allowed.");
  }

  return {
    eoaAddress,
    fileName,
    contentType,
    imageID: buildImageID(eoaAddress, fileName),
  };
}

async function createPinataSignedUploadURL(
  request: NormalizedDirectUploadRequest,
  env: Env
): Promise<string> {
  const pinataJWT = resolveRequiredEnvValue(env.PINATA_JWT, "PINATA_JWT");
  const pinataGroupID = resolveRequiredEnvValue(env.PINATA_GROUP_ID, "PINATA_GROUP_ID");

  const expires = parseBoundedInteger(
    env.PINATA_SIGN_EXPIRES_SECONDS ?? "120",
    15,
    3600,
    120
  );
  const maxFileSize = parseBoundedInteger(
    env.PINATA_MAX_FILE_SIZE_BYTES ?? "10485760",
    1024,
    104_857_600,
    10_485_760
  );

  const body = {
    date: Math.floor(Date.now() / 1000),
    expires,
    max_file_size: maxFileSize,
    allow_mime_types: [request.contentType],
    group_id: pinataGroupID,
    keyvalues: {
      app: "knot",
      kind: "profile_avatar",
      owner: request.eoaAddress,
      image_id: request.imageID,
    },
    filename: request.fileName,
  };

  const response = await fetch("https://uploads.pinata.cloud/v3/files/sign", {
    method: "POST",
    headers: {
      authorization: `Bearer ${pinataJWT}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  if (!response.ok) {
    throw new Error(`Pinata sign request failed (${response.status}): ${text}`);
  }

  let payload: unknown;
  try {
    payload = JSON.parse(text);
  } catch {
    throw new Error("Pinata sign response was not valid JSON.");
  }

  if (!payload || typeof payload !== "object") {
    throw new Error("Pinata sign response is malformed.");
  }

  const signedURL = (payload as { data?: unknown }).data;
  if (typeof signedURL !== "string" || signedURL.trim() === "") {
    throw new Error("Pinata sign response is missing signed URL.");
  }

  let parsed: URL;
  try {
    parsed = new URL(signedURL);
  } catch {
    throw new Error("Pinata sign response returned invalid URL.");
  }
  if (!parsed.host) {
    throw new Error("Pinata sign response returned invalid URL.");
  }
  return signedURL;
}

function resolvePinataGatewayBaseURL(env: Env): string {
  const configured = resolveRequiredEnvValue(
    env.PINATA_GATEWAY_BASE_URL,
    "PINATA_GATEWAY_BASE_URL"
  );

  let normalized = configured.includes("://") ? configured : `https://${configured}`;
  normalized = normalized.replace(/\/+$/, "");
  if (!normalized.toLowerCase().includes("/ipfs")) {
    normalized = `${normalized}/ipfs`;
  }
  normalized = `${normalized}/`;

  let parsed: URL;
  try {
    parsed = new URL(normalized);
  } catch {
    throw new Error("Invalid PINATA_GATEWAY_BASE_URL.");
  }
  if (!parsed.host) {
    throw new Error("Invalid PINATA_GATEWAY_BASE_URL.");
  }
  return normalized;
}

function resolveRequiredEnvValue(value: string | undefined, name: string): string {
  const trimmed = (value ?? "").trim();
  if (!trimmed) {
    throw new Error(`${name} is not configured.`);
  }
  return trimmed;
}

function sanitizeFileName(value: string): string {
  const normalized = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-+|-+$/g, "");
  return normalized.slice(0, 96);
}

function buildImageID(eoaAddress: string, fileName: string): string {
  const timestamp = new Date().toISOString().replace(/[-:.TZ]/g, "");
  const randomSuffix = randomHex(4);
  return `avatars/${eoaAddress}/${timestamp}-${randomSuffix}-${fileName}`;
}

function randomHex(bytes: number): string {
  const value = new Uint8Array(bytes);
  crypto.getRandomValues(value);
  return Array.from(value)
    .map((item) => item.toString(16).padStart(2, "0"))
    .join("");
}

function normalizeTxEnvelopes(input: unknown): RelayTxEnvelope[] {
  if (!Array.isArray(input)) {
    throw new BadRequestError("Relay tx list must be an array.");
  }

  return input.map((item) => {
    if (!item || typeof item !== "object") {
      throw new BadRequestError("Invalid relay tx envelope.");
    }

    const tx = item as { chainId?: unknown; request?: unknown };
    const chainId = Number(tx.chainId);
    if (!Number.isFinite(chainId) || chainId <= 0) {
      throw new BadRequestError("Invalid chainId in relay tx envelope.");
    }

    if (!tx.request || typeof tx.request !== "object") {
      throw new BadRequestError("Missing request object in relay tx envelope.");
    }

    return {
      chainId,
      request: tx.request as Record<string, unknown>,
    };
  });
}

function assertRelayTransactionsMatchAccount(account: string, txs: RelayTxEnvelope[]): void {
  for (const tx of txs) {
    const from = relayTxFromAddress(tx.request, tx.chainId);
    if (from !== account) {
      throw new BadRequestError(`Relay tx account mismatch for chain ${tx.chainId}.`);
    }
    assertAuthorizationAddressesMatchAccount(account, tx.request, tx.chainId);
  }
}

async function resolveFreeInitializationTransactionIndexes(
  account: string,
  txs: RelayTxEnvelope[],
  env: Env
): Promise<Set<number>> {
  const indexesByChain = new Map<number, number[]>();
  for (let i = 0; i < txs.length; i += 1) {
    const chainID = txs[i].chainId;
    const indexes = indexesByChain.get(chainID) ?? [];
    indexes.push(i);
    indexesByChain.set(chainID, indexes);
  }

  const freeIndexes = new Set<number>();
  for (const [chainID, indexes] of indexesByChain.entries()) {
    const needsInitialization = await accountNeedsInitialization(chainID, account, env);
    const authTxIndexes: number[] = [];
    const initAuthTxIndexes: number[] = [];

    for (const index of indexes) {
      const request = txs[index].request;
      if (!hasEip7702Authorization(request)) {
        continue;
      }
      authTxIndexes.push(index);
      if (isInitializationTransactionRequest(account, request, chainID)) {
        initAuthTxIndexes.push(index);
      }
    }

    if (needsInitialization) {
      if (initAuthTxIndexes.length !== 1) {
        throw new BadRequestError(
          `Account requires exactly one initialize transaction with EIP-7702 authorization on chain ${chainID}.`
        );
      }
      if (authTxIndexes.length !== initAuthTxIndexes.length) {
        throw new BadRequestError(
          `When initialization is required, EIP-7702 authorization must be attached to the initialize transaction on chain ${chainID}.`
        );
      }
      freeIndexes.add(initAuthTxIndexes[0]);
    }
  }

  return freeIndexes;
}

async function accountNeedsInitialization(chainID: number, account: string, env: Env): Promise<boolean> {
  const rpcURL = buildGelatoRPCURL(chainID, env);
  const chain = defineChain({
    id: chainID,
    name: `chain-${chainID}`,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [rpcURL] } },
  });
  const client = createPublicClient({
    chain,
    transport: http(rpcURL),
  });

  const code = await client.getCode({ address: getAddress(account) });
  return !code || code === "0x";
}

function hasEip7702Authorization(request: Record<string, unknown>): boolean {
  if (request.eip7702Auth && typeof request.eip7702Auth === "object") {
    return true;
  }
  return Array.isArray(request.authorizationList) && request.authorizationList.length > 0;
}

function isInitializationTransactionRequest(
  account: string,
  request: Record<string, unknown>,
  chainId: number
): boolean {
  const from = relayTxFromAddress(request, chainId);
  if (from !== account) {
    throw new BadRequestError(`Authorization sender mismatch for chain ${chainId}.`);
  }

  const toRaw = request.to;
  if (typeof toRaw !== "string" || toRaw.trim() === "") {
    throw new BadRequestError(`Missing request.to for chain ${chainId}.`);
  }
  const to = normalizeAddress(toRaw);
  if (to !== account) {
    return false;
  }

  const data = relayTxData(request, chainId);
  return data.startsWith(INITIALIZE_SELECTOR);
}

function relayTxFromAddress(request: Record<string, unknown>, chainId: number): string {
  const fromRaw = request.from;
  if (typeof fromRaw !== "string" || fromRaw.trim() === "") {
    throw new BadRequestError(`Missing request.from for chain ${chainId}.`);
  }
  return normalizeAddress(fromRaw);
}

function relayTxData(request: Record<string, unknown>, chainId: number): string {
  const dataRaw = request.data;
  if (typeof dataRaw !== "string" || dataRaw.trim() === "") {
    throw new BadRequestError(`Missing request.data for chain ${chainId}.`);
  }
  const normalized = dataRaw.trim().toLowerCase();
  if (!/^0x[0-9a-f]*$/.test(normalized)) {
    throw new BadRequestError(`Invalid request.data for chain ${chainId}.`);
  }
  return normalized;
}

function assertAuthorizationAddressesMatchAccount(
  account: string,
  request: Record<string, unknown>,
  chainId: number
): void {
  const checkAddressMatch = (value: unknown, fieldName: string): void => {
    if (typeof value !== "string" || value.trim() === "") {
      return;
    }
    const normalized = normalizeAddress(value);
    if (normalized !== account) {
      throw new BadRequestError(`${fieldName} account mismatch for chain ${chainId}.`);
    }
  };

  const eip7702Auth = request.eip7702Auth;
  if (eip7702Auth && typeof eip7702Auth === "object") {
    checkAddressMatch((eip7702Auth as Record<string, unknown>).address, "request.eip7702Auth.address");
  }

  const authorizationList = request.authorizationList;
  if (Array.isArray(authorizationList)) {
    for (let i = 0; i < authorizationList.length; i += 1) {
      const auth = authorizationList[i];
      if (!auth || typeof auth !== "object") {
        continue;
      }
      checkAddressMatch(
        (auth as Record<string, unknown>).address,
        `request.authorizationList[${i}].address`
      );
    }
  }
}

async function fundAccount(
  recipientAddress: string,
  env: Env,
  rpcByChain: Record<number, string>
): Promise<void> {
  const privateKey = normalizePrivateKey(env.FAUCET_PRIVATE_KEY ?? "");
  const account = privateKeyToAccount(privateKey);
  const recipient = getAddress(recipientAddress);

  await Promise.all(
    Object.entries(rpcByChain).map(async ([chainIDRaw, rpcURL]) => {
      const chainID = Number(chainIDRaw);
      if (!Number.isFinite(chainID)) {
        return;
      }
      try {
        await fundOnChain(chainID, rpcURL, account, recipient);
      } catch (error) {
        const reason = error instanceof Error ? error.message : "unknown chain funding error";
        console.error(`faucet chain ${chainID} failed`, reason);
      }
    })
  );
}

async function fundOnChain(
  chainID: number,
  rpcURL: string,
  account: ReturnType<typeof privateKeyToAccount>,
  recipient: Address
): Promise<void> {
  const chain = defineChain({
    id: chainID,
    name: `chain-${chainID}`,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [rpcURL] } },
  });

  const publicClient = createPublicClient({
    chain,
    transport: http(rpcURL),
  });
  const walletClient = createWalletClient({
    account,
    chain,
    transport: http(rpcURL),
  });

  const feeEstimate = await publicClient.estimateFeesPerGas();
  const gasPrice = feeEstimate.gasPrice ?? (await publicClient.getGasPrice());
  const maxPriorityFeePerGas = feeEstimate.maxPriorityFeePerGas ?? gasPrice / 10n;
  const maxFeePerGas = feeEstimate.maxFeePerGas ?? gasPrice * 2n;

  const usdcAddress = TESTNET_USDC_BY_CHAIN[chainID];
  if (usdcAddress) {
    try {
      const usdcCalldata = encodeFunctionData({
        abi: ERC20_TRANSFER_ABI,
        functionName: "transfer",
        args: [recipient, USDC_DRIP_AMOUNT],
      });
      const usdcHash = await walletClient.sendTransaction({
        account,
        to: usdcAddress,
        data: usdcCalldata,
        gas: 65_000n,
        maxFeePerGas,
        maxPriorityFeePerGas,
      });
      console.log(`faucet chain ${chainID} usdc tx ${usdcHash}`);
    } catch (error) {
      const reason = error instanceof Error ? error.message : "unknown usdc transfer error";
      console.error(`faucet chain ${chainID} usdc transfer failed`, reason);
    }
  }

  const ethHash = await walletClient.sendTransaction({
    account,
    to: recipient,
    value: ETH_DRIP_WEI,
    gas: 21_000n,
    maxFeePerGas,
    maxPriorityFeePerGas,
  });
  console.log(`faucet chain ${chainID} eth tx ${ethHash}`);
}

function resolveFaucetRPCByChain(env: Env): Record<number, string> {
  const values: Record<number, string> = {};

  const maybeAdd = (chainID: number, rpcURL: string | undefined): void => {
    const value = (rpcURL ?? "").trim();
    if (!value) {
      return;
    }

    let parsed: URL;
    try {
      parsed = new URL(value);
    } catch {
      throw new BadRequestError(`Invalid faucet RPC URL for chain ${chainID}.`);
    }
    if (!parsed.host) {
      throw new BadRequestError(`Invalid faucet RPC URL for chain ${chainID}.`);
    }
    values[chainID] = value;
  };

  maybeAdd(11155111, env.FAUCET_RPC_SEPOLIA);
  maybeAdd(84532, env.FAUCET_RPC_BASE_SEPOLIA);
  maybeAdd(421614, env.FAUCET_RPC_ARB_SEPOLIA);

  if (Object.keys(values).length === 0) {
    throw new BadRequestError("Faucet RPC URLs are not configured.");
  }
  return values;
}

function normalizePrivateKey(value: string): Hex {
  const trimmed = value.trim().toLowerCase();
  if (!trimmed) {
    throw new BadRequestError("Faucet private key is not configured.");
  }

  const normalized = trimmed.startsWith("0x") ? trimmed : `0x${trimmed}`;
  if (!/^0x[0-9a-f]{64}$/.test(normalized)) {
    throw new BadRequestError("Invalid faucet private key.");
  }
  return normalized as Hex;
}

async function quoteTotalMicros(txs: RelayTxEnvelope[], env: Env): Promise<bigint> {
  let total = 0n;
  for (const tx of txs) {
    const raw = await sendGelatoRpc(tx.chainId, "relayer_getFeeQuote", [tx.request], env);
    total += parseFeeMicros(raw);
  }
  return total;
}

function parseFeeMicros(raw: unknown): bigint {
  if (typeof raw === "string") {
    return parseBigint(raw);
  }

  if (!raw || typeof raw !== "object") {
    throw new BadRequestError("Invalid fee quote response from relayer.");
  }

  const dict = raw as Record<string, unknown>;
  const amountValue =
    pickString(dict, ["amount", "fee", "feeAmount", "estimatedFee"]) ??
    pickString(dict, ["total"]) ??
    pickString(dict, ["result"]);

  if (!amountValue) {
    throw new BadRequestError("Relayer quote missing fee amount.");
  }

  return parseBigint(amountValue);
}

async function sendRelayTransaction(
  method: "relayer_sendTransaction" | "relayer_sendTransactionSync",
  tx: RelayTxEnvelope,
  env: Env
): Promise<RelaySubmission> {
  const raw = await sendGelatoRpc(tx.chainId, method, [tx.request], env);

  if (typeof raw === "string") {
    return { id: raw };
  }

  if (!raw || typeof raw !== "object") {
    throw new BadRequestError("Relayer submission response missing identifier.");
  }

  const dict = raw as Record<string, unknown>;
  const id =
    pickString(dict, ["taskId", "taskID", "id", "relayTaskId", "submissionId"]) ??
    pickString(dict, ["hash", "transactionHash", "txHash"]);

  if (!id) {
    throw new BadRequestError("Relayer submission response missing identifier.");
  }

  const transactionHash = pickString(dict, ["transactionHash", "txHash", "hash"]);
  return { id, transactionHash: transactionHash ?? undefined };
}

function parseRelayStatus(raw: unknown, fallbackID: string): RelayStatus {
  if (!raw || typeof raw !== "object") {
    throw new BadRequestError("Relayer status response is malformed.");
  }

  const root = raw as Record<string, unknown>;
  const nestedTask = (root.task ?? null) as Record<string, unknown> | null;
  const scope = nestedTask ?? root;

  const rawStatus =
    pickString(scope, ["status", "taskState", "taskStatus", "state"]) ??
    pickString(root, ["status", "taskState", "taskStatus", "state"]);

  if (!rawStatus) {
    throw new BadRequestError("Relayer status response missing status field.");
  }

  const id =
    pickString(scope, ["taskId", "taskID", "id", "relayTaskId", "submissionId"]) ?? fallbackID;

  return {
    id,
    rawStatus,
    state: normalizeRelayState(rawStatus),
    transactionHash:
      pickString(scope, ["transactionHash", "txHash", "hash"]) ??
      pickString(root, ["transactionHash", "txHash", "hash"]) ??
      undefined,
    blockNumber: pickString(scope, ["blockNumber"]) ?? pickString(root, ["blockNumber"]) ?? undefined,
    failureReason:
      pickString(scope, ["reason", "error", "failureReason", "message"]) ??
      pickString(root, ["reason", "error", "failureReason", "message"]) ??
      undefined,
  };
}

function normalizeRelayState(rawStatus: string): string {
  const value = rawStatus.trim().toLowerCase();
  if (value.includes("success") || value.includes("exec_success") || value.includes("executed")) {
    return "executed";
  }
  if (value.includes("fail") || value.includes("error")) {
    return "failed";
  }
  if (value.includes("revert")) {
    return "reverted";
  }
  if (value.includes("cancel")) {
    return "cancelled";
  }
  if (value.includes("wait")) {
    return "waiting";
  }
  if (value.includes("pending") || value.includes("queued")) {
    return "pending";
  }
  return "unknown";
}

function pickString(dict: Record<string, unknown>, keys: string[]): string | null {
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

async function sendGelatoRpc(chainId: number, method: string, params: unknown[], env: Env): Promise<unknown> {
  const endpoint = buildGelatoRPCURL(chainId, env);
  const body = JSON.stringify({
    jsonrpc: "2.0",
    id: `relay-${Date.now()}-${Math.random().toString(16).slice(2)}`,
    method,
    params,
  });

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body,
  });

  const text = await response.text();
  if (!response.ok) {
    throw new BadRequestError(`Relayer RPC request failed (${response.status}): ${text}`);
  }

  let payload: unknown;
  try {
    payload = JSON.parse(text);
  } catch {
    throw new BadRequestError("Relayer RPC returned non-JSON response.");
  }

  if (!payload || typeof payload !== "object") {
    throw new BadRequestError("Relayer RPC response is malformed.");
  }

  const rpc = payload as { error?: { message?: string }; result?: unknown };
  if (rpc.error) {
    throw new BadRequestError(rpc.error.message ?? "Relayer RPC returned an error.");
  }

  return rpc.result;
}

function buildGelatoRPCURL(chainId: number, env: Env): string {
  const template =
    (env.GELATO_RPC_TEMPLATE ?? "https://api.gelato.cloud/rpc/{chainId}?apiKey={apiKey}").trim();
  return template
    .replaceAll("{chainId}", String(chainId))
    .replaceAll("{apiKey}", encodeURIComponent(env.GELATO_API_KEY));
}

async function readTankState(env: Env, account: string, supportMode: SupportMode, usdcDecimals: number): Promise<TankState> {
  const key = buildTankKey(account, supportMode);
  const raw = await env.GAS_TANK_KV.get(key);
  if (!raw) {
    const initial = parseUsdToMicros(env.INITIAL_CREDIT_USDC ?? "2", usdcDecimals);
    return { balanceMicros: initial, initialized: false };
  }

  try {
    const payload = JSON.parse(raw) as { balanceMicros?: string };
    if (!payload.balanceMicros) {
      throw new Error("missing balanceMicros");
    }
    return { balanceMicros: BigInt(payload.balanceMicros), initialized: true };
  } catch {
    const initial = parseUsdToMicros(env.INITIAL_CREDIT_USDC ?? "2", usdcDecimals);
    return { balanceMicros: initial, initialized: false };
  }
}

async function writeTankState(
  env: Env,
  account: string,
  supportMode: SupportMode,
  balanceMicros: bigint,
  usdcDecimals: number
): Promise<void> {
  const key = buildTankKey(account, supportMode);
  await env.GAS_TANK_KV.put(
    key,
    JSON.stringify({
      balanceMicros: balanceMicros.toString(),
      balanceUsdc: formatUsd(balanceMicros, usdcDecimals),
      updatedAt: new Date().toISOString(),
    })
  );
}

function buildTankKey(account: string, supportMode: SupportMode): string {
  return `gas-tank:${supportMode}:${account.toLowerCase()}`;
}

function resolveUsdcDecimals(env: Env): number {
  const parsed = Number(env.USDC_DECIMALS ?? "6");
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 18) {
    return 6;
  }
  return parsed;
}

function resolveFloorMicros(mode: SupportMode, env: Env, usdcDecimals: number): bigint {
  switch (mode) {
    case "LIMITED_TESTNET":
      return parseUsdToMicros(env.FLOOR_LIMITED_TESTNET_USDC ?? "-2", usdcDecimals);
    case "LIMITED_MAINNET":
      return parseUsdToMicros(env.FLOOR_LIMITED_MAINNET_USDC ?? "-2", usdcDecimals);
    case "FULL_MAINNET":
      return parseUsdToMicros(env.FLOOR_FULL_MAINNET_USDC ?? "0", usdcDecimals);
  }
}

function sanitizePaymentOptions(options: PaymentOption[]): PaymentOption[] {
  return options
    .filter((item) => {
      if (!item || typeof item !== "object") {
        return false;
      }
      if (!Number.isFinite(Number(item.chainId)) || Number(item.chainId) <= 0) {
        return false;
      }
      if (!item.tokenAddress || !item.symbol) {
        return false;
      }
      const amount = Number(item.amount);
      return Number.isFinite(amount) && amount > 0;
    })
    .map((item) => ({
      chainId: Number(item.chainId),
      tokenAddress: String(item.tokenAddress),
      symbol: String(item.symbol),
      amount: String(item.amount),
    }));
}

function parseUsdToMicros(value: string, decimals: number): bigint {
  const normalized = value.trim();
  if (!normalized) {
    return 0n;
  }

  const isNegative = normalized.startsWith("-");
  const unsigned = isNegative ? normalized.slice(1) : normalized;
  const [whole, fractionalRaw = ""] = unsigned.split(".");
  const fractional = (fractionalRaw + "0".repeat(decimals)).slice(0, decimals);

  const wholePart = whole === "" ? 0n : BigInt(whole);
  const fractionalPart = fractional === "" ? 0n : BigInt(fractional);
  const scale = 10n ** BigInt(decimals);
  const micros = wholePart * scale + fractionalPart;
  return isNegative ? -micros : micros;
}

function formatUsd(value: bigint, decimals: number): string {
  const isNegative = value < 0n;
  const absolute = isNegative ? -value : value;
  const scale = 10n ** BigInt(decimals);
  const whole = absolute / scale;
  const fraction = absolute % scale;
  const fractionStr = fraction.toString().padStart(decimals, "0").replace(/0+$/, "");
  const unsigned = fractionStr ? `${whole.toString()}.${fractionStr}` : whole.toString();
  return isNegative ? `-${unsigned}` : unsigned;
}

function parseBigint(value: string): bigint {
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

function parseInteger(value: string | null, field: string): number {
  const parsed = Number(value ?? "");
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new BadRequestError(`Invalid ${field}.`);
  }
  return parsed;
}

function parseBoundedInteger(
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

function normalizeAddress(value: string): string {
  const normalized = value.trim().toLowerCase();
  if (!isAddress(normalized)) {
    throw new BadRequestError("Invalid account address.");
  }
  return getAddress(normalized).toLowerCase();
}

async function authorizeRequest(request: Request, env: Env, rawBody: string): Promise<void> {
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
  return bytesToHex(new Uint8Array(mac));
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
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

function jsonResponse(payload: unknown, status = 200): Response {
  return corsResponse(
    new Response(JSON.stringify(payload), {
      status,
      headers: JSON_HEADERS,
    })
  );
}

function corsResponse(response: Response): Response {
  response.headers.set("Access-Control-Allow-Origin", "*");
  response.headers.set("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  response.headers.set("Access-Control-Allow-Headers", "authorization,content-type,x-relay-timestamp,x-relay-signature");
  return response;
}

class BadRequestError extends Error {}

class AuthError extends Error {}

class PaymentRequiredError extends Error {
  readonly account: string;
  readonly supportMode: SupportMode;
  readonly estimatedDebitMicros: bigint;
  readonly balanceMicros: bigint;
  readonly postDebitMicros: bigint;
  readonly minimumAllowedMicros: bigint;
  readonly requiredTopUpMicros: bigint;
  readonly suggestedTopUpMicros: bigint;
  readonly usdcDecimals: number;
  readonly paymentOptions: PaymentOption[];

  constructor(input: {
    account: string;
    supportMode: SupportMode;
    estimatedDebitMicros: bigint;
    balanceMicros: bigint;
    postDebitMicros: bigint;
    minimumAllowedMicros: bigint;
    requiredTopUpMicros: bigint;
    suggestedTopUpMicros: bigint;
    usdcDecimals: number;
    paymentOptions: PaymentOption[];
  }) {
    super("payment_required");
    this.account = input.account;
    this.supportMode = input.supportMode;
    this.estimatedDebitMicros = input.estimatedDebitMicros;
    this.balanceMicros = input.balanceMicros;
    this.postDebitMicros = input.postDebitMicros;
    this.minimumAllowedMicros = input.minimumAllowedMicros;
    this.requiredTopUpMicros = input.requiredTopUpMicros;
    this.suggestedTopUpMicros = input.suggestedTopUpMicros;
    this.usdcDecimals = input.usdcDecimals;
    this.paymentOptions = input.paymentOptions;
  }
}

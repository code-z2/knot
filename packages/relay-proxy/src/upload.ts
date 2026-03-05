import { PinataSDK } from "pinata";
import { SUPPORT_MODES } from "./constants";
import { BadRequestError } from "./errors";
import type { Env, NormalizedDirectUploadRequestModel, DirectUploadRequestModel, SupportMode } from "./relay/models";
import {
  jsonResponse,
  normalizeAddress,
  parseBoundedInteger,
  randomHex,
  resolveRequiredEnvValue,
  sanitizeFileName,
} from "./utils";

export async function handleDirectImageUpload(rawBody: string, env: Env): Promise<Response> {
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

function parseDirectUploadRequest(rawBody: string): NormalizedDirectUploadRequestModel {
  let payload: unknown;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    throw new BadRequestError("Invalid JSON body.");
  }

  if (!payload || typeof payload !== "object") {
    throw new BadRequestError("Invalid direct upload payload.");
  }

  const request = payload as Partial<DirectUploadRequestModel>;
  const eoaAddress = normalizeAddress(String(request.eoaAddress ?? ""));
  const fileName = sanitizeFileName(String(request.fileName ?? ""));
  if (!fileName) {
    throw new BadRequestError("Invalid fileName.");
  }

  const contentType = String(request.contentType ?? "").trim().toLowerCase();
  if (!contentType.startsWith("image/")) {
    throw new BadRequestError("Only image uploads are allowed.");
  }

  const modeRaw = String(request.supportMode ?? "").trim();
  if (!SUPPORT_MODES.has(modeRaw)) {
    throw new BadRequestError("Missing or invalid supportMode.");
  }

  return {
    eoaAddress,
    fileName,
    contentType,
    supportMode: modeRaw as SupportMode,
    imageID: buildImageID(eoaAddress, fileName),
  };
}

async function createPinataSignedUploadURL(
  payload: NormalizedDirectUploadRequestModel,
  env: Env,
): Promise<string> {
  const jwt = resolveRequiredEnvValue(env.PINATA_JWT, "PINATA_JWT");
  const expiresSeconds = parseBoundedInteger(env.PINATA_SIGN_EXPIRES_SECONDS ?? "180", 60, 900, 180);
  const maxFileSize = parseBoundedInteger(env.PINATA_MAX_FILE_SIZE_BYTES ?? "10485760", 1024, 25_000_000, 10_485_760);
  const groupID = resolvePinataGroupID(payload.supportMode, env);

  const pinata = new PinataSDK({ pinataJwt: jwt });

  try {
    const signedUrl = await pinata.upload.public.createSignedURL({
      expires: expiresSeconds,
      name: payload.fileName,
      groupId: groupID,
      maxFileSize: maxFileSize,
      keyvalues: {
        owner: payload.eoaAddress,
        imageID: payload.imageID,
        supportMode: payload.supportMode,
        source: "knot-relay",
      },
    });

    if (typeof signedUrl !== "string" || signedUrl.trim() === "") {
      throw new BadRequestError("Pinata SDK returned missing or invalid signed URL.");
    }

    return signedUrl.trim();
  } catch (err: unknown) {
    throw new BadRequestError(`Pinata signed URL request failed: ${err instanceof Error ? err.message : String(err)}`);
  }
}

function resolvePinataGroupID(supportMode: SupportMode, env: Env): string {
  const raw = (env.PINATA_GROUP_CONFIG ?? "").trim();
  if (!raw) {
    throw new BadRequestError("PINATA_GROUP_CONFIG is not configured.");
  }

  let config: Record<string, string>;
  try {
    config = JSON.parse(raw) as Record<string, string>;
  } catch {
    throw new BadRequestError("PINATA_GROUP_CONFIG is not valid JSON.");
  }

  const groupID = (config[supportMode] ?? "").trim();
  if (!groupID) {
    throw new BadRequestError(`No Pinata group configured for mode: ${supportMode}`);
  }

  return groupID;
}

function resolvePinataGatewayBaseURL(env: Env): string {
  const raw = resolveRequiredEnvValue(env.PINATA_GATEWAY_BASE_URL, "PINATA_GATEWAY_BASE_URL")
    .trim()
    .replace(/\/+$/, "");
  try {
    const parsed = new URL(raw);
    return `${parsed.origin}/ipfs`;
  } catch {
    throw new BadRequestError("Invalid PINATA_GATEWAY_BASE_URL.");
  }
}

function buildImageID(eoaAddress: string, fileName: string): string {
  const timestamp = new Date().toISOString().replace(/[-:.TZ]/g, "");
  const randomSuffix = randomHex(4);
  return `avatars/${eoaAddress}/${timestamp}-${randomSuffix}-${fileName}`;
}

import { SUPPORT_MODES } from '../shared/constants';
import { BadRequestError } from '../shared/errors';
import { jsonResponse } from '../shared/http';
import type {
    Env,
    NormalizedDirectUploadRequestModel,
    DirectUploadRequestModel,
    SupportMode,
} from '../shared/types';
import { normalizeAddress, parseBoundedInteger } from '../shared/validation';
import { resolveRequiredEnvValue } from '../shared/http';

import { createPinataSignedUploadURL, resolvePinataGatewayBaseURL } from './pinata';

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
        throw new BadRequestError('Invalid JSON body.');
    }

    if (!payload || typeof payload !== 'object') {
        throw new BadRequestError('Invalid direct upload payload.');
    }

    const request = payload as Partial<DirectUploadRequestModel>;
    const eoaAddress = normalizeAddress(String(request.eoaAddress ?? ''));
    const fileName = sanitizeFileName(String(request.fileName ?? ''));
    if (!fileName) {
        throw new BadRequestError('Invalid fileName.');
    }

    const contentType = String(request.contentType ?? '')
        .trim()
        .toLowerCase();
    if (!contentType.startsWith('image/')) {
        throw new BadRequestError('Only image uploads are allowed.');
    }

    const modeRaw = String(request.supportMode ?? '').trim();
    if (!SUPPORT_MODES.has(modeRaw as SupportMode)) {
        throw new BadRequestError('Missing or invalid supportMode.');
    }

    return {
        eoaAddress,
        fileName,
        contentType,
        supportMode: modeRaw as SupportMode,
        imageID: buildImageID(eoaAddress, fileName),
    };
}

// ---------------------------------------------------------------------------
// Private Helpers
// ---------------------------------------------------------------------------

function sanitizeFileName(value: string): string {
    const normalized = value
        .trim()
        .replace(/[^a-zA-Z0-9._-]/g, '-')
        .replace(/-+/g, '-')
        .replace(/^-+|-+$/g, '');
    return normalized.slice(0, 120);
}

function randomHex(bytes: number): string {
    const value = new Uint8Array(bytes);
    crypto.getRandomValues(value);
    return Array.from(value)
        .map((item) => item.toString(16).padStart(2, '0'))
        .join('');
}

function buildImageID(eoaAddress: string, fileName: string): string {
    const timestamp = new Date().toISOString().replace(/[-:.TZ]/g, '');
    const randomSuffix = randomHex(4);
    return `avatars/${eoaAddress}/${timestamp}-${randomSuffix}-${fileName}`;
}

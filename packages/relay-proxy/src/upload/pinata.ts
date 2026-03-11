/**
 * Pinata IPFS integration — signed upload URL generation.
 */
import { PinataSDK } from 'pinata';

import { BadRequestError } from '../shared/errors';
import { resolveRequiredEnvValue } from '../shared/http';
import type { Env, NormalizedDirectUploadRequestModel, SupportMode } from '../shared/types';
import { parseBoundedInteger } from '../shared/validation';

export async function createPinataSignedUploadURL(
    payload: NormalizedDirectUploadRequestModel,
    env: Env,
): Promise<string> {
    const jwt = resolveRequiredEnvValue(env.PINATA_JWT, 'PINATA_JWT');
    const expiresSeconds = parseBoundedInteger(
        env.PINATA_SIGN_EXPIRES_SECONDS ?? '180',
        60,
        900,
        180,
    );
    const maxFileSize = parseBoundedInteger(
        env.PINATA_MAX_FILE_SIZE_BYTES ?? '10485760',
        1024,
        25_000_000,
        10_485_760,
    );
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
                source: 'knot-relay',
            },
        });

        if (typeof signedUrl !== 'string' || signedUrl.trim() === '') {
            throw new BadRequestError('Pinata SDK returned missing or invalid signed URL.');
        }

        return signedUrl.trim();
    } catch (err: unknown) {
        throw new BadRequestError(
            `Pinata signed URL request failed: ${err instanceof Error ? err.message : String(err)}`,
        );
    }
}

export function resolvePinataGatewayBaseURL(env: Env): string {
    const raw = resolveRequiredEnvValue(env.PINATA_GATEWAY_BASE_URL, 'PINATA_GATEWAY_BASE_URL')
        .trim()
        .replace(/\/+$/, '');
    try {
        const parsed = new URL(raw);
        return `${parsed.origin}/ipfs`;
    } catch {
        throw new BadRequestError('Invalid PINATA_GATEWAY_BASE_URL.');
    }
}

function resolvePinataGroupID(supportMode: SupportMode, env: Env): string {
    const config = env.PINATA_GROUP_CONFIG;
    const groupID = (config[supportMode] ?? '').trim();
    if (!groupID) {
        throw new BadRequestError(`No Pinata group configured for mode: ${supportMode}`);
    }

    return groupID;
}

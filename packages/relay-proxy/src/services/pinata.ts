import { PINATA_MAX_FILE_SIZE_BYTES, PINATA_SIGN_EXPIRES_SECONDS } from '@/constants';
import type { CloudflareBindings, CreateAppOptions, UploadConfig, UploadRuntime } from '@/types';
import { parseBoundedInteger } from '@/utils';
import { PinataSDK } from 'pinata';

function createUploadConfig(env: CloudflareBindings): UploadConfig {
    return {
        gatewayBaseURL: env.PINATA_GATEWAY_BASE_URL.trim()
            .replace(/\/+$/, '')
            .replace(/\/ipfs$/, ''),
        imageGroupId: env.PINATA_IMAGE_GROUP_ID,
        maxFileSizeBytes: parseBoundedInteger(
            env.PINATA_MAX_FILE_SIZE_BYTES,
            1_024,
            25_000_000,
            PINATA_MAX_FILE_SIZE_BYTES,
        ),
        signExpiresSeconds: parseBoundedInteger(
            env.PINATA_SIGN_EXPIRES_SECONDS,
            60,
            900,
            PINATA_SIGN_EXPIRES_SECONDS,
        ),
    };
}

function createUploadRuntime(env: CloudflareBindings): UploadRuntime {
    const config = createUploadConfig(env);
    const pinata = new PinataSDK({
        pinataJwt: env.PINATA_JWT,
    });

    return {
        config,
        signer: {
            async createImageUploadURL(input) {
                const signedURL = await pinata.upload.public.createSignedURL({
                    expires: config.signExpiresSeconds,
                    groupId: config.imageGroupId,
                    keyvalues: {
                        imageID: input.imageID,
                        purpose: input.purpose,
                        source: 'knot-relay',
                        userId: input.userId,
                    },
                    maxFileSize: config.maxFileSizeBytes,
                    name: input.fileName,
                });

                if (typeof signedURL !== 'string' || signedURL.length === 0) {
                    throw new Error('pinata_sign_failed');
                }

                return signedURL;
            },
        },
    };
}

export function createUploadClient(env: CloudflareBindings, options: CreateAppOptions) {
    return options.upload ?? createUploadRuntime(env);
}

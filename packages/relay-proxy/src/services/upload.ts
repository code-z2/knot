import type { ImageUploadOptionsParams, ImageUploadOptionsResult, UploadRuntime } from '@/types';
import { createImageID } from '@/utils';

export async function issueImageUploadOptions(
    runtime: UploadRuntime,
    input: ImageUploadOptionsParams & { userId: string },
) {
    if (input.byteLength > runtime.config.maxFileSizeBytes) {
        return {
            ok: false,
            error: 'file_too_large',
        };
    }

    const imageID = createImageID({
        fileName: input.fileName,
        purpose: input.purpose,
        userId: input.userId,
    });

    try {
        const uploadURL = await runtime.signer.createImageUploadURL({
            byteLength: input.byteLength,
            contentType: input.contentType,
            fileName: input.fileName,
            imageID,
            purpose: input.purpose,
            userId: input.userId,
        });

        return {
            ok: true,
            result: {
                expiresAt: Date.now() + runtime.config.signExpiresSeconds * 1_000,
                gatewayBaseURL: `${runtime.config.gatewayBaseURL}/ipfs`,
                imageID,
                uploadURL,
            } satisfies ImageUploadOptionsResult,
        };
    } catch {
        return {
            ok: false,
            error: 'upload_unavailable',
        };
    }
}

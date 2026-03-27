import type { CreateAppOptions } from '../../src/types';

export function createTestUpload(): NonNullable<CreateAppOptions['upload']> {
    return {
        config: {
            gatewayBaseURL: 'https://gateway.pinata.cloud',
            imageGroupId: 'pinata-group-id',
            maxFileSizeBytes: 10 * 1024 * 1024,
            signExpiresSeconds: 180,
        },
        signer: {
            async createImageUploadURL() {
                return 'https://uploads.pinata.cloud/v3/files/signed-upload';
            },
        },
    };
}

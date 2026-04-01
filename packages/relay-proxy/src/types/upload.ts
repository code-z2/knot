export type UploadPurpose = 'avatar';

export type ImageUploadOptionsParams = {
    byteLength: number;
    contentType: string;
    fileName: string;
    purpose: UploadPurpose;
};

export type ImageUploadOptionsResult = {
    expiresAt: number;
    gatewayBaseURL: string;
    imageID: string;
    uploadURL: string;
};

export type UploadConfig = {
    gatewayBaseURL: string;
    imageGroupId: string;
    maxFileSizeBytes: number;
    signExpiresSeconds: number;
};

export type UploadSignerInput = {
    byteLength: number;
    contentType: string;
    fileName: string;
    imageID: string;
    purpose: UploadPurpose;
    userId: string;
};

export type UploadSigner = {
    createImageUploadURL: (input: UploadSignerInput) => Promise<string>;
};

export type UploadRuntime = {
    config: UploadConfig;
    signer: UploadSigner;
};

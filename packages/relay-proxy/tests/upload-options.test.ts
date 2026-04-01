import { describe, expect, it } from 'bun:test';

import type { RpcFailure, RpcSuccess } from '../src/types';
import { createTestApp } from './helpers/app';
import { registerUser } from './helpers/auth-flow';
import { jsonHeaders, readJson } from './helpers/http';

describe('relay proxy upload routes', () => {
    it('issues image upload options for an authenticated user', async () => {
        const { app } = createTestApp();
        const { verifyBody } = await registerUser(app, {
            appAttestKeyId: 'attest-key-upload',
            credentialId: 'credential-upload',
            userId: 'user-upload',
        });

        const response = await app.request('http://localhost/v1/upload/image/options', {
            method: 'POST',
            headers: {
                authorization: `Bearer ${verifyBody.result.accessToken}`,
                ...jsonHeaders(),
            },
            body: JSON.stringify({
                id: 'upload_options',
                jsonrpc: '2.0',
                method: 'knot_imageUploadOptions',
                params: {
                    byteLength: 1_024,
                    contentType: 'image/jpeg',
                    fileName: 'profile-photo.jpg',
                    purpose: 'avatar',
                },
            }),
        });

        expect(response.status).toBe(200);

        const body = await readJson<
            RpcSuccess<{
                expiresAt: number;
                gatewayBaseURL: string;
                imageID: string;
                uploadURL: string;
            }>
        >(response);

        expect(body).toEqual({
            id: 'upload_options',
            jsonrpc: '2.0',
            result: {
                expiresAt: expect.any(Number),
                gatewayBaseURL: 'https://gateway.pinata.cloud/ipfs',
                imageID: expect.any(String),
                uploadURL: 'https://uploads.pinata.cloud/v3/files/signed-upload',
            },
        });

        expect(body.result.imageID.startsWith('images/avatar/user-upload/')).toBe(true);
        expect(body.result.imageID.endsWith('profile-photo.jpg')).toBe(true);
    });

    it('rejects upload options without an active session', async () => {
        const { app } = createTestApp();
        const response = await app.request('http://localhost/v1/upload/image/options', {
            method: 'POST',
            headers: jsonHeaders(),
            body: JSON.stringify({
                id: 'upload_unauthorized',
                jsonrpc: '2.0',
                method: 'knot_imageUploadOptions',
                params: {
                    byteLength: 1_024,
                    contentType: 'image/jpeg',
                    fileName: 'avatar.jpg',
                    purpose: 'avatar',
                },
            }),
        });

        expect(response.status).toBe(401);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'upload_unauthorized',
            jsonrpc: '2.0',
            error: {
                code: -32001,
                message: 'unauthorized',
                reason: 'unauthorized',
            },
        });
    });

    it('rejects oversized upload requests', async () => {
        const { app, upload } = createTestApp();
        const { verifyBody } = await registerUser(app, {
            appAttestKeyId: 'attest-key-upload-limit',
            credentialId: 'credential-upload-limit',
            userId: 'user-upload-limit',
        });

        const response = await app.request('http://localhost/v1/upload/image/options', {
            method: 'POST',
            headers: {
                authorization: `Bearer ${verifyBody.result.accessToken}`,
                ...jsonHeaders(),
            },
            body: JSON.stringify({
                id: 'upload_too_large',
                jsonrpc: '2.0',
                method: 'knot_imageUploadOptions',
                params: {
                    byteLength: upload.config.maxFileSizeBytes + 1,
                    contentType: 'image/jpeg',
                    fileName: 'avatar.jpg',
                    purpose: 'avatar',
                },
            }),
        });

        expect(response.status).toBe(400);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'upload_too_large',
            jsonrpc: '2.0',
            error: {
                code: -32000,
                message: 'file_too_large',
                reason: 'file_too_large',
            },
        });
    });

    it('rejects non-image content types', async () => {
        const { app } = createTestApp();
        const { verifyBody } = await registerUser(app, {
            appAttestKeyId: 'attest-key-upload-type',
            credentialId: 'credential-upload-type',
            userId: 'user-upload-type',
        });

        const response = await app.request('http://localhost/v1/upload/image/options', {
            method: 'POST',
            headers: {
                authorization: `Bearer ${verifyBody.result.accessToken}`,
                ...jsonHeaders(),
            },
            body: JSON.stringify({
                id: 'upload_bad_type',
                jsonrpc: '2.0',
                method: 'knot_imageUploadOptions',
                params: {
                    byteLength: 1_024,
                    contentType: 'application/pdf',
                    fileName: 'avatar.pdf',
                    purpose: 'avatar',
                },
            }),
        });

        expect(response.status).toBe(400);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'upload_bad_type',
            jsonrpc: '2.0',
            error: {
                code: -32602,
                details: [
                    {
                        message: expect.any(String),
                        path: 'params.contentType',
                    },
                ],
                message: 'invalid_params:params.contentType',
                reason: 'invalid_params:params.contentType',
            },
        });
    });

    it('rejects invalid file names at the schema boundary', async () => {
        const { app } = createTestApp();
        const { verifyBody } = await registerUser(app, {
            appAttestKeyId: 'attest-key-upload-name',
            credentialId: 'credential-upload-name',
            userId: 'user-upload-name',
        });

        const response = await app.request('http://localhost/v1/upload/image/options', {
            method: 'POST',
            headers: {
                authorization: `Bearer ${verifyBody.result.accessToken}`,
                ...jsonHeaders(),
            },
            body: JSON.stringify({
                id: 'upload_bad_name',
                jsonrpc: '2.0',
                method: 'knot_imageUploadOptions',
                params: {
                    byteLength: 1_024,
                    contentType: 'image/jpeg',
                    fileName: 'profile photo!!.jpg',
                    purpose: 'avatar',
                },
            }),
        });

        expect(response.status).toBe(400);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'upload_bad_name',
            jsonrpc: '2.0',
            error: {
                code: -32602,
                details: [
                    {
                        message: expect.any(String),
                        path: 'params.fileName',
                    },
                ],
                message: 'invalid_params:params.fileName',
                reason: 'invalid_params:params.fileName',
            },
        });
    });

    it('returns upload_unavailable when the signer fails', async () => {
        const testApp = createTestApp({
            upload: {
                config: {
                    gatewayBaseURL: 'https://gateway.pinata.cloud',
                    imageGroupId: 'pinata-group-id',
                    maxFileSizeBytes: 10 * 1024 * 1024,
                    signExpiresSeconds: 180,
                },
                signer: {
                    async createImageUploadURL() {
                        throw new Error('boom');
                    },
                },
            },
        });

        const { verifyBody } = await registerUser(testApp.app, {
            appAttestKeyId: 'attest-key-upload-fail',
            credentialId: 'credential-upload-fail',
            userId: 'user-upload-fail',
        });

        const response = await testApp.app.request('http://localhost/v1/upload/image/options', {
            method: 'POST',
            headers: {
                authorization: `Bearer ${verifyBody.result.accessToken}`,
                ...jsonHeaders(),
            },
            body: JSON.stringify({
                id: 'upload_unavailable',
                jsonrpc: '2.0',
                method: 'knot_imageUploadOptions',
                params: {
                    byteLength: 1_024,
                    contentType: 'image/jpeg',
                    fileName: 'avatar.jpg',
                    purpose: 'avatar',
                },
            }),
        });

        expect(response.status).toBe(500);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'upload_unavailable',
            jsonrpc: '2.0',
            error: {
                code: -32000,
                message: 'upload_unavailable',
                reason: 'upload_unavailable',
            },
        });
    });
});

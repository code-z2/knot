import { describe, expect, it } from 'bun:test';

import type { RpcFailure, RpcSuccess } from '../src/types';
import { createTestApp } from './helpers/app';
import { beginLogin, finishLogin, registerUser } from './helpers/auth-flow';
import { jsonHeaders, readJson } from './helpers/http';

function createRegistrationCredential(id: string) {
    return {
        attestationObject: 'attestation-object',
        clientDataJSON: 'client-data-json',
        id,
        publicKey: `0x${'11'.repeat(33)}` as const,
        raw: {},
    };
}

describe('relay proxy register and login routes', () => {
    it('completes register options and verify', async () => {
        const { app } = createTestApp();
        const { optionsBody, optionsResponse, verifyBody, verifyResponse } = await registerUser(app, {
            appAttestKeyId: 'attest-key-register',
            credentialId: 'credential-register',
            userId: 'user-register',
        });

        expect(optionsResponse.status).toBe(200);
        expect(optionsBody.result.challengeId.length).toBeGreaterThan(0);
        expect(optionsBody.result.appAttestChallenge.startsWith('0x')).toBe(true);

        expect(verifyResponse.status).toBe(200);
        expect(verifyBody).toEqual({
            id: 'register_verify',
            jsonrpc: '2.0',
            result: {
                accessToken: expect.any(String),
                appAttestKeyId: 'attest-key-register',
                expiresAt: expect.any(Number),
                refreshToken: expect.any(String),
                sessionId: expect.any(String),
                userId: 'user-register',
            },
        });
    });

    it('rejects duplicate user registration', async () => {
        const { app } = createTestApp();
        await registerUser(app, {
            appAttestKeyId: 'attest-key-duplicate-1',
            credentialId: 'credential-duplicate-1',
            userId: 'user-duplicate',
        });

        const duplicateOptionsResponse = await app.request('http://localhost/v1/user/register/options', {
            method: 'POST',
            headers: jsonHeaders(),
            body: JSON.stringify({
                id: 'register_options_duplicate',
                jsonrpc: '2.0',
                method: 'knot_userRegisterOptions',
                params: {
                    userId: 'user-duplicate',
                },
            }),
        });

        const duplicateOptionsBody = await readJson<RpcSuccess<{ challengeId: string }>>(duplicateOptionsResponse);

        const duplicateVerifyResponse = await app.request('http://localhost/v1/user/register/verify', {
            method: 'POST',
            headers: jsonHeaders(),
            body: JSON.stringify({
                id: 'register_verify_duplicate',
                jsonrpc: '2.0',
                method: 'knot_userRegisterVerify',
                params: {
                appAttestKeyId: 'attest-key-duplicate-2',
                attestation: 'attestation:duplicate',
                challengeId: duplicateOptionsBody.result.challengeId,
                credential: createRegistrationCredential('credential-duplicate-2'),
            },
        }),
    });

        expect(duplicateVerifyResponse.status).toBe(400);
        expect(await readJson<RpcFailure>(duplicateVerifyResponse)).toEqual({
            id: 'register_verify_duplicate',
            jsonrpc: '2.0',
            error: {
                code: -32000,
                message: 'user_already_exists',
                reason: 'user_already_exists',
            },
        });
    });

    it('completes login options and verify for an existing user', async () => {
        const { app } = createTestApp();
        await registerUser(app, {
            appAttestKeyId: 'attest-key-login',
            credentialId: 'credential-login',
            userId: 'user-login',
        });

        const { body: optionsBody, response: optionsResponse } = await beginLogin(app, 'credential-login');
        const verifyResponse = await finishLogin(app, {
            appAttestKeyId: 'attest-key-login',
            challengeId: optionsBody.result.challengeId,
        });

        expect(optionsResponse.status).toBe(200);
        expect(verifyResponse.status).toBe(200);
        expect(await readJson<RpcSuccess<{
            accessToken: string;
            appAttestKeyId: string;
            expiresAt: number;
            refreshToken: string;
            sessionId: string;
            userId: string;
        }>>(verifyResponse)).toEqual({
            id: 'login_verify',
            jsonrpc: '2.0',
            result: {
                accessToken: expect.any(String),
                appAttestKeyId: 'attest-key-login',
                expiresAt: expect.any(Number),
                refreshToken: expect.any(String),
                sessionId: expect.any(String),
                userId: 'user-login',
            },
        });
    });

    it('rejects login options for an unknown user', async () => {
        const { app } = createTestApp();
        const { body, response } = await beginLogin(app, 'missing-credential');

        expect(response.status).toBe(400);
        expect(body as unknown as RpcFailure).toEqual({
            id: 'login_options',
            jsonrpc: '2.0',
            error: {
                code: -32000,
                message: 'user_not_found',
                reason: 'user_not_found',
            },
        });
    });

    it('rejects login verify when passkey verification fails', async () => {
        const { app } = createTestApp();
        await registerUser(app, {
            appAttestKeyId: 'attest-key-login-fail',
            credentialId: 'credential-login',
            userId: 'user-login-fail',
        });

        const { body: optionsBody } = await beginLogin(app, 'credential-login');
        const verifyResponse = await finishLogin(app, {
            appAttestKeyId: 'attest-key-login-fail',
            challengeId: optionsBody.result.challengeId,
            responseId: 'credential-mismatch',
        });

        expect(verifyResponse.status).toBe(401);
        expect(await readJson<RpcFailure>(verifyResponse)).toEqual({
            id: 'login_verify',
            jsonrpc: '2.0',
            error: {
                code: -32001,
                message: 'verification_failed',
                reason: 'verification_failed',
            },
        });
    });
});

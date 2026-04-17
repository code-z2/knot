import { describe, expect, it } from 'bun:test';

import type { RpcFailure, RpcSuccess } from '../src/types';
import { createTestApp, attachHighFidelityTestRoute } from './helpers/app';
import { registerUser } from './helpers/auth-flow';
import { jsonHeaders, readJson } from './helpers/http';

const LOGOUT_USER = '0x2000000000000000000000000000000000000001';
const HIGH_FIDELITY_USER = '0x2000000000000000000000000000000000000002';
const INVALID_ASSERTION_USER = '0x2000000000000000000000000000000000000003';

describe('relay proxy auth fidelity', () => {
    it('uses low fidelity auth for logout', async () => {
        const { app } = createTestApp();
        const { verifyBody } = await registerUser(app, {
            appAttestKeyId: 'attest-key-logout',
            credentialId: 'credential-logout',
            userId: LOGOUT_USER,
        });

        const logoutResponse = await app.request('http://localhost/v1/user/logout', {
            method: 'POST',
            headers: {
                authorization: `Bearer ${verifyBody.result.accessToken}`,
                ...jsonHeaders(),
            },
            body: JSON.stringify({
                id: 'logout',
                jsonrpc: '2.0',
                method: 'knot_userLogout',
                params: {},
            }),
        });

        expect(logoutResponse.status).toBe(200);
        expect(
            await readJson<
                RpcSuccess<{
                    loggedOut: boolean;
                    sessionId: string;
                    userId: string;
                }>
            >(logoutResponse),
        ).toEqual({
            id: 'logout',
            jsonrpc: '2.0',
            result: {
                loggedOut: true,
                sessionId: expect.any(String),
                userId: LOGOUT_USER,
            },
        });
    });

    it('uses high fidelity auth for protected routes', async () => {
        const testApp = createTestApp();
        attachHighFidelityTestRoute(testApp.app, {
            auth: testApp.auth,
        });

        const { verifyBody } = await registerUser(testApp.app, {
            appAttestKeyId: 'attest-key-high',
            credentialId: 'credential-high',
            userId: HIGH_FIDELITY_USER,
        });

        const unauthorizedResponse = await testApp.app.request('http://localhost/v1/protected/high', {
            method: 'POST',
            headers: {
                authorization: `Bearer ${verifyBody.result.accessToken}`,
                ...jsonHeaders(),
            },
            body: JSON.stringify({
                id: 'protected_high_missing',
                jsonrpc: '2.0',
                method: 'knot_userLogout',
                params: {},
            }),
        });

        expect(unauthorizedResponse.status).toBe(401);
        expect(await readJson<RpcFailure>(unauthorizedResponse)).toEqual({
            id: 'protected_high_missing',
            jsonrpc: '2.0',
            error: {
                code: -32001,
                message: 'unauthorized',
                reason: 'unauthorized',
            },
        });

        const authorizedResponse = await testApp.app.request('http://localhost/v1/protected/high', {
            method: 'POST',
            headers: {
                authorization: `Bearer ${verifyBody.result.accessToken}`,
                'x-knot-app-attest-assertion': 'assertion:protected',
                'x-knot-app-attest-key-id': verifyBody.result.appAttestKeyId,
                'x-knot-nonce': 'nonce-protected',
                'x-knot-timestamp': String(Date.now()),
                ...jsonHeaders(),
            },
            body: JSON.stringify({
                id: 'protected_high_ok',
                jsonrpc: '2.0',
                method: 'knot_userLogout',
                params: {},
            }),
        });

        expect(authorizedResponse.status).toBe(200);
        expect(await readJson<RpcSuccess<{ ok: boolean; userId: string }>>(authorizedResponse)).toEqual({
            id: 'protected_high_ok',
            jsonrpc: '2.0',
            result: {
                ok: true,
                userId: HIGH_FIDELITY_USER,
            },
        });
    });

    it('rejects high fidelity auth when the attestation assertion is invalid', async () => {
        const testApp = createTestApp();
        attachHighFidelityTestRoute(testApp.app, {
            auth: testApp.auth,
        });

        const { verifyBody } = await registerUser(testApp.app, {
            appAttestKeyId: 'attest-key-invalid',
            credentialId: 'credential-invalid',
            userId: INVALID_ASSERTION_USER,
        });

        const response = await testApp.app.request('http://localhost/v1/protected/high', {
            method: 'POST',
            headers: {
                authorization: `Bearer ${verifyBody.result.accessToken}`,
                'x-knot-app-attest-assertion': 'bad-assertion',
                'x-knot-app-attest-key-id': verifyBody.result.appAttestKeyId,
                'x-knot-nonce': 'nonce-invalid',
                'x-knot-timestamp': String(Date.now()),
                ...jsonHeaders(),
            },
            body: JSON.stringify({
                id: 'protected_high_invalid',
                jsonrpc: '2.0',
                method: 'knot_userLogout',
                params: {},
            }),
        });

        expect(response.status).toBe(401);
        expect(await readJson<RpcFailure>(response)).toEqual({
            id: 'protected_high_invalid',
            jsonrpc: '2.0',
            error: {
                code: -32001,
                message: 'unauthorized',
                reason: 'unauthorized',
            },
        });
    });
});

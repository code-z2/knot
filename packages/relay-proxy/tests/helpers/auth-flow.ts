import type {
    RpcSuccess,
    UserRegisterOptionsResult,
    UserLoginOptionsResult,
} from '../../src/types';
import { jsonHeaders, readJson } from './http';

type RegisterSessionResult = {
    accessToken: string;
    appAttestKeyId: string;
    expiresAt: number;
    refreshToken: string;
    sessionId: string;
    userId: string;
};

function createRegistrationCredential(id: string) {
    return {
        attestationObject: 'attestation-object',
        clientDataJSON: 'client-data-json',
        id,
        publicKey: `0x${'11'.repeat(33)}` as const,
        raw: {},
    };
}

function createAuthenticationResponse(id: string) {
    return {
        id,
        metadata: {
            authenticatorData: `0x${'22'.repeat(32)}` as const,
            clientDataJSON: 'client-data-json',
        },
        raw: {},
        signature: `0x${'33'.repeat(64)}` as const,
    };
}

export async function registerUser(
    app: ReturnType<typeof import('./app').createTestApp>['app'],
    input: {
        appAttestKeyId: string;
        credentialId: string;
        userId: string;
    },
) {
    const optionsResponse = await app.request('http://localhost/v1/user/register/options', {
        method: 'POST',
        headers: jsonHeaders(),
        body: JSON.stringify({
            id: 'register_options',
            jsonrpc: '2.0',
            method: 'knot_userRegisterOptions',
            params: {
                userId: input.userId,
            },
        }),
    });

    const optionsBody = await readJson<RpcSuccess<UserRegisterOptionsResult>>(optionsResponse);

    const verifyResponse = await app.request('http://localhost/v1/user/register/verify', {
        method: 'POST',
        headers: jsonHeaders(),
        body: JSON.stringify({
            id: 'register_verify',
            jsonrpc: '2.0',
            method: 'knot_userRegisterVerify',
            params: {
                appAttestKeyId: input.appAttestKeyId,
                attestation: 'attestation:register',
                challengeId: optionsBody.result.challengeId,
                credential: createRegistrationCredential(input.credentialId),
            },
        }),
    });

    return {
        optionsBody,
        optionsResponse,
        verifyBody: await readJson<RpcSuccess<RegisterSessionResult>>(verifyResponse),
        verifyResponse,
    };
}

export async function beginLogin(
    app: ReturnType<typeof import('./app').createTestApp>['app'],
    credentialId: string,
) {
    const response = await app.request('http://localhost/v1/user/login/options', {
        method: 'POST',
        headers: jsonHeaders(),
        body: JSON.stringify({
            id: 'login_options',
            jsonrpc: '2.0',
            method: 'knot_userLoginOptions',
            params: {
                credentialId,
            },
        }),
    });

    return {
        body: await readJson<RpcSuccess<UserLoginOptionsResult>>(response),
        response,
    };
}

export async function finishLogin(
    app: ReturnType<typeof import('./app').createTestApp>['app'],
    input: {
        appAttestAssertion?: string;
        appAttestKeyId: string;
        challengeId: string;
        responseId?: string;
    },
) {
    const response = await app.request('http://localhost/v1/user/login/verify', {
        method: 'POST',
        headers: jsonHeaders(),
        body: JSON.stringify({
            id: 'login_verify',
            jsonrpc: '2.0',
            method: 'knot_userLoginVerify',
            params: {
                appAttestAssertion: input.appAttestAssertion ?? 'assertion:login',
                appAttestKeyId: input.appAttestKeyId,
                challengeId: input.challengeId,
                response: createAuthenticationResponse(input.responseId ?? 'credential-login'),
            },
        }),
    });

    return response;
}

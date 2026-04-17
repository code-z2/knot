import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';

import { RPC_APP_ERRORS } from '@/errors';
import { rpcHook, userLoginOptionsSchema, userLoginVerifySchema } from '@/schemas/rpc';
import { createAuthClient } from '@/services/auth';
import { consumeChallenge, issueChallenge } from '@/services/challenge';
import { getPasskey } from '@/services/passkey';
import { createSession } from '@/services/session';
import { getAttestation, getUser, updateAttestation } from '@/services/user';
import type { AppBindings, CreateAppOptions, UserLoginOptionsResult } from '@/types';
import { rpcAppError, rpcResult } from '@/utils';

/**
 * User login routes (`/v1/user/login/*`).
 *
 * Login mirrors registration's begin/verify split but resolves the passkey
 * owner **before** issuing the challenge so the flow is bound to a known,
 * active user from the start.
 *
 * ### Flow
 *
 * 1. **`POST /options`** — client sends a `credentialId` (stored locally
 *    after a previous registration). The server looks up the passkey and its
 *    owning user, then returns a challenge and `CredentialRequestOptions`.
 *
 * 2. **`POST /verify`** — client returns the signed passkey response and an
 *    App Attest assertion. The server verifies both, bumps the attestation
 *    sign count, and issues a new session.
 *
 * User status is checked at both steps — a revoked user cannot begin or
 * complete a login.
 */
export function createUserLoginRoutes(options: CreateAppOptions = {}) {
    const routes = new Hono<AppBindings>();

    routes.post('/options', zValidator('json', userLoginOptionsSchema, rpcHook), async (c) => {
        const rpc = c.req.valid('json');

        const client = createAuthClient(c.env, options);
        const passkey = await getPasskey(client.store, rpc.params.credentialId);

        if (!passkey) {
            return rpcAppError(c, rpc.id, RPC_APP_ERRORS.userNotFound);
        }

        // Status lives on the user record. A revoked user's passkeys are
        // implicitly revoked — no separate passkey status needed.
        const user = await getUser(client.store, passkey.userId);

        if (!user || user.status !== 'active') {
            return rpcAppError(c, rpc.id, RPC_APP_ERRORS.userNotFound);
        }

        const challenge = await issueChallenge(client.store, {
            credentialId: rpc.params.credentialId,
            kind: 'user_login',
            userId: passkey.userId,
        });

        const result: UserLoginOptionsResult = {
            appAttestChallenge: challenge.challenge,
            challengeId: challenge.id,
            options: client.verifiers.passkey.getAuthenticationOptions(rpc.params.credentialId, challenge.challenge),
        };

        return c.json(rpcResult(rpc.id, result));
    });

    routes.post('/verify', zValidator('json', userLoginVerifySchema, rpcHook), async (c) => {
        const rpc = c.req.valid('json');

        const client = createAuthClient(c.env, options);
        const now = Date.now();
        const challenge = await consumeChallenge(client.store, rpc.params.challengeId, 'user_login');

        if (!challenge || !challenge.credentialId) {
            return rpcAppError(c, rpc.id, RPC_APP_ERRORS.challengeNotFound);
        }

        // Load all three records needed for verification.
        const passkey = await getPasskey(client.store, challenge.credentialId);
        const appAttestation = await getAttestation(client.store, {
            id: 'key_id',
            value: rpc.params.appAttestKeyId,
        });

        const user = await getUser(client.store, passkey?.userId ?? '');

        if (!passkey || !user || user.status !== 'active' || !appAttestation || appAttestation.status !== 'active') {
            return rpcAppError(c, rpc.id, RPC_APP_ERRORS.userNotFound);
        }

        try {
            // Verify the passkey signature first — cheapest check.
            const passkeyValid = client.verifiers.passkey.verifyAuthentication({
                challenge: challenge.challenge,
                publicKey: passkey.publicKey,
                response: rpc.params.response,
            });

            if (!passkeyValid) {
                return rpcAppError(c, rpc.id, RPC_APP_ERRORS.verificationFailed);
            }

            // Then verify the App Attest assertion and bump the sign counter.
            const assertion = client.verifiers.appAttest.verifyAssertion({
                assertion: rpc.params.appAttestAssertion,
                keyId: rpc.params.appAttestKeyId,
                payload: challenge.challenge,
                publicKey: appAttestation.publicKey,
                signCount: appAttestation.signCount,
            });

            await updateAttestation(client.store, {
                keyId: rpc.params.appAttestKeyId,
                now,
                signCount: assertion.signCount,
            });

            const session = await createSession(client.store, {
                appAttestKeyId: rpc.params.appAttestKeyId,
                now,
                userId: passkey.userId,
            });

            return c.json(
                rpcResult(rpc.id, {
                    accessToken: session.accessToken,
                    appAttestKeyId: session.appAttestKeyId,
                    expiresAt: session.expiresAt,
                    refreshToken: session.refreshToken,
                    sessionId: session.id,
                    userId: passkey.userId,
                }),
            );
        } catch {
            return rpcAppError(c, rpc.id, RPC_APP_ERRORS.verificationFailed);
        }
    });

    return routes;
}

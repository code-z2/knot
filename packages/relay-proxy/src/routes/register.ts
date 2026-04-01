import { zValidator } from '@hono/zod-validator';
import { Hono } from 'hono';

import { RPC_APP_ERRORS } from '@/errors';
import { rpcHook, userRegisterOptionsSchema, userRegisterVerifySchema } from '@/schemas/rpc';
import { createAuthClient } from '@/services/auth';
import { consumeChallenge, issueChallenge } from '@/services/challenge';
import { createPasskey } from '@/services/passkey';
import { createSession } from '@/services/session';
import { createAttestation, createUser } from '@/services/user';
import type { AppBindings, CreateAppOptions, UserRegisterOptionsResult } from '@/types';
import { rpcAppError, rpcResult } from '@/utils';

/**
 * User registration routes (`/v1/user/register/*`).
 *
 * Registration is an unauthenticated, two-step begin/verify flow. A single
 * one-time challenge is shared by both the passkey ceremony and the App Attest
 * attestation so the two proofs are cryptographically bound.
 *
 * ### Flow
 *
 * 1. **`POST /options`** — client sends a `userId`. The server issues a
 *    challenge and returns passkey `CredentialCreationOptions` plus an
 *    `appAttestChallenge` for the device attestation.
 *
 * 2. **`POST /verify`** — client returns the signed passkey credential and
 *    the App Attest attestation. On success the server creates the user,
 *    passkey, and attestation records and issues a session.
 *
 * Both endpoints use `zValidator` for request validation — the zod schema
 * enforces the JSON-RPC envelope **and** the params shape in a single pass.
 * Handlers access the validated body via `c.req.valid('json')`.
 */
export function createUserRegisterRoutes(options: CreateAppOptions = {}) {
    const routes = new Hono<AppBindings>();

    routes.post('/options', zValidator('json', userRegisterOptionsSchema, rpcHook), async (c) => {
        const rpc = c.req.valid('json');

        const client = createAuthClient(c.env, options);
        const challenge = await issueChallenge(client.store, {
            kind: 'user_register',
            userId: rpc.params.userId,
        });

        const result: UserRegisterOptionsResult = {
            appAttestChallenge: challenge.challenge,
            challengeId: challenge.id,
            options: client.verifiers.passkey.getRegistrationOptions(
                rpc.params.userId,
                challenge.challenge,
            ),
        };

        return c.json(rpcResult(rpc.id, result));
    });

    routes.post('/verify', zValidator('json', userRegisterVerifySchema, rpcHook), async (c) => {
        const rpc = c.req.valid('json');

        const client = createAuthClient(c.env, options);
        const now = Date.now();
        const challenge = await consumeChallenge(
            client.store,
            rpc.params.challengeId,
            'user_register',
        );

        if (!challenge || !challenge.userId) {
            return rpcAppError(c, rpc.id, RPC_APP_ERRORS.challengeNotFound);
        }

        try {
            // Verify both proofs against the same challenge.
            const registration = client.verifiers.passkey.verifyRegistration({
                challenge: challenge.challenge,
                credential: rpc.params.credential,
            });

            const attestation = client.verifiers.appAttest.verifyAttestation({
                attestation: rpc.params.attestation,
                challenge: challenge.challenge,
                keyId: rpc.params.appAttestKeyId,
            });

            // Persist user, passkey, and attestation atomically.
            const user = await createUser(client.store, {
                now,
                userId: challenge.userId,
            });

            if (!user) {
                return rpcAppError(c, rpc.id, RPC_APP_ERRORS.userAlreadyExists);
            }

            await createPasskey(client.store, {
                counter: registration.counter,
                credentialId: registration.credential.id,
                now,
                publicKey: registration.credential.publicKey as string,
                userId: user.id,
            });

            await createAttestation(client.store, {
                environment: attestation.environment,
                keyId: attestation.keyId,
                now,
                publicKey: attestation.publicKey,
                signCount: 0,
            });

            // Issue an initial session so the client is authenticated
            // immediately after registration without a separate login round-trip.
            const session = await createSession(client.store, {
                appAttestKeyId: rpc.params.appAttestKeyId,
                now,
                userId: user.id,
            });

            return c.json(
                rpcResult(rpc.id, {
                    accessToken: session.accessToken,
                    appAttestKeyId: session.appAttestKeyId,
                    expiresAt: session.expiresAt,
                    refreshToken: session.refreshToken,
                    sessionId: session.id,
                    userId: user.id,
                }),
            );
        } catch {
            return rpcAppError(c, rpc.id, RPC_APP_ERRORS.verificationFailed);
        }
    });

    return routes;
}

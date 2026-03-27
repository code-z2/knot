import type { MiddlewareHandler } from 'hono';

import { RPC_APP_ERRORS } from '@/errors';
import { createAuthClient } from '@/services/auth';
import { consumeNonce } from '@/services/nonce';
import { getSession } from '@/services/session';
import { getAttestation, updateAttestation } from '@/services/user';
import type { AppBindings, AuthFidelity, CreateAppOptions, RpcId } from '@/types';
import { rpcAppError, buildAppAttestPayload, parseJsonRecord } from '@/utils';

/**
 * Session and device-attestation middleware.
 *
 * Runs **after** `zValidator` so the request body is already validated. This
 * middleware is self-contained: it reads `rawBody` and the RPC `id` directly
 * from the request (Hono caches the body, so the read is free after
 * zValidator's initial parse) rather than relying on context variables.
 *
 * ### Fidelity levels
 *
 * | Level  | What is checked                                              |
 * |--------|--------------------------------------------------------------|
 * | `low`  | Valid, non-expired bearer session.                           |
 * | `high` | Session **+** a fresh App Attest assertion bound to the      |
 * |        | exact request body, route path, nonce, and timestamp.        |
 *
 * On success the middleware sets `session` on the Hono context so downstream
 * handlers can identify the caller.
 */
export function auth(
    fidelity: AuthFidelity,
    options: CreateAppOptions = {},
): MiddlewareHandler<AppBindings> {
    return async (c, next) => {
        const rawBody = await c.req.text();
        const rpcId = parseJsonRecord<{ id: RpcId }>(rawBody)?.id ?? null;
        const authorization = c.req.header('authorization');

        if (!authorization?.startsWith('Bearer ')) {
            return rpcAppError(c, rpcId, RPC_APP_ERRORS.unauthorized);
        }

        const client = createAuthClient(c.env, options);
        const now = Date.now();
        const session = await getSession(client.store, authorization.slice('Bearer '.length), now);

        if (!session) {
            return rpcAppError(c, rpcId, RPC_APP_ERRORS.unauthorized);
        }

        if (fidelity === 'low') {
            c.set('session', session);
            await next();
            return;
        }

        const appAttestAssertion = c.req.header('x-knot-app-attest-assertion');
        const appAttestKeyId = c.req.header('x-knot-app-attest-key-id');
        const nonce = c.req.header('x-knot-nonce');
        const timestamp = c.req.header('x-knot-timestamp');

        if (!appAttestAssertion || !appAttestKeyId || !nonce || !timestamp) {
            return rpcAppError(c, rpcId, RPC_APP_ERRORS.unauthorized);
        }

        if (session.appAttestKeyId !== appAttestKeyId) {
            return rpcAppError(c, rpcId, RPC_APP_ERRORS.unauthorized);
        }

        const nonceConsumed = await consumeNonce(client.store, {
            appAttestKeyId,
            nonce,
            now,
            timestamp,
        });

        if (!nonceConsumed) {
            return rpcAppError(c, rpcId, RPC_APP_ERRORS.unauthorized);
        }

        const appAttestation = await getAttestation(client.store, {
            id: 'key_id',
            value: appAttestKeyId,
        });

        if (!appAttestation || appAttestation.status !== 'active') {
            return rpcAppError(c, rpcId, RPC_APP_ERRORS.unauthorized);
        }

        const payload = await buildAppAttestPayload({
            body: rawBody,
            method: c.req.method,
            nonce,
            path: new URL(c.req.url).pathname,
            timestamp,
        });

        try {
            const verification = client.verifiers.appAttest.verifyAssertion({
                assertion: appAttestAssertion,
                keyId: appAttestKeyId,
                payload,
                publicKey: appAttestation.publicKey,
                signCount: appAttestation.signCount,
            });

            await updateAttestation(client.store, {
                keyId: appAttestKeyId,
                now,
                signCount: verification.signCount,
            });
        } catch {
            return rpcAppError(c, rpcId, RPC_APP_ERRORS.unauthorized);
        }

        c.set('session', session);
        await next();
    };
}

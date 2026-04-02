/**
 * RPC request schemas — single source of truth for runtime validation and
 * static types across all relay-proxy routes.
 *
 * Each schema is a full JSON-RPC 2.0 envelope (`id`, `jsonrpc`, `method`,
 * `params`) built via {@link rpcEnvelope}. The `method` field is a
 * `z.literal()` so the schema doubles as a route guard — a request whose
 * method doesn't match the route's schema is rejected before the handler runs.
 *
 * Schemas are consumed by `@hono/zod-validator` as middleware:
 *
 * ```ts
 * routes.post('/options', zValidator('json', userLoginOptionsSchema, rpcHook), handler);
 * ```
 *
 * The handler then accesses the fully-typed, validated body via
 * `c.req.valid('json')` — no casts, no manual param checks.
 *
 * @module
 */
import { RPC_APP_ERRORS, invalidParams } from '@/errors';
import type { RpcId } from '@/types';
import { rpcAppError } from '@/utils';
import type { Context } from 'hono';
import { Authentication, Registration } from 'webauthx/server';
import { z } from 'zod';

const addressSchema = z.string().regex(/^0x[a-fA-F0-9]{40}$/);
const hexValueSchema = z.string().regex(/^0x[a-fA-F0-9]+$/);
const bytesSchema = z.string().regex(/^0x[a-fA-F0-9]*$/);

/**
 * Serialized WebAuthn registration credential (`ox/webauthn` Credential<true>).
 *
 * Enforces the exact wire format the client must send after
 * `navigator.credentials.create()` → `Credential.serialize()`. Fields that
 * carry opaque platform data (`raw`) are left as `z.any()` because their
 * internal shape is validated downstream by the passkey verifier.
 */
const credentialSchema: z.ZodType<Registration.Credential> = z.object({
    attestationObject: z.string().min(1),
    clientDataJSON: z.string().min(1),
    id: z.string().min(1),
    publicKey: z.custom<`0x${string}`>(),
    raw: z.any(),
});

/**
 * Serialized WebAuthn authentication response (`ox/webauthn` Authentication.Response<true>).
 *
 * Same philosophy as {@link credentialSchema}: required fields are strict,
 * `raw` is passed through for the verifier.
 */
const authResponseSchema: z.ZodType<Authentication.Response> = z.object({
    id: z.string().min(1),
    metadata: z.object({
        authenticatorData: z.custom<`0x${string}`>(),
        challengeIndex: z.number().optional(),
        clientDataJSON: z.string().min(1),
        typeIndex: z.number().optional(),
        userVerificationRequired: z.boolean().optional(),
    }),
    signature: z.custom<`0x${string}`>(),
    raw: z.any(),
});

const eip7702AuthSchema = z
    .object({
        address: addressSchema,
        chainId: hexValueSchema,
        nonce: hexValueSchema,
        r: bytesSchema,
        s: bytesSchema,
        yParity: hexValueSchema,
    })
    .strict();

const rpcUserOperationSchema = z
    .object({
        callData: bytesSchema,
        callGasLimit: hexValueSchema,
        eip7702Auth: eip7702AuthSchema.optional(),
        factory: addressSchema.optional(),
        factoryData: bytesSchema.optional(),
        maxFeePerGas: z.literal('0x0'),
        maxPriorityFeePerGas: z.literal('0x0'),
        nonce: hexValueSchema,
        paymaster: addressSchema.optional(),
        paymasterData: bytesSchema.optional(),
        paymasterPostOpGasLimit: hexValueSchema.optional(),
        paymasterVerificationGasLimit: hexValueSchema.optional(),
        preVerificationGas: hexValueSchema,
        sender: addressSchema,
        signature: bytesSchema,
        verificationGasLimit: hexValueSchema,
    })
    .strict();

/**
 * Builds a JSON-RPC 2.0 envelope schema for a given method and params shape.
 *
 * The returned schema validates:
 * - `id`      — string, number, or null (JSON-RPC spec)
 * - `jsonrpc` — must be exactly `"2.0"`
 * - `method`  — must be the literal `M` (acts as a route guard)
 * - `params`  — validated by the provided `P` schema
 */
function rpcEnvelope<M extends string, P extends z.ZodType>(method: M, params: P) {
    return z.object({
        id: z.union([z.string(), z.number(), z.null()]),
        jsonrpc: z.literal('2.0'),
        method: z.literal(method),
        params,
    });
}

/**
 * Shared error hook for `zValidator`. On validation failure, returns a
 * JSON-RPC error response with the request `id` (if recoverable from the
 * partial payload) so the client can correlate the error.
 */
export function rpcHook(result: { success: boolean; data: { id?: RpcId } }, c: Context) {
    if (!result.success) {
        const issues =
            'error' in result && result.error instanceof z.ZodError ? result.error.issues : [];
        const firstIssue = issues[0];
        const path = firstIssue ? firstIssue.path.map(String).join('.') : '';
        const details = issues.map((issue) => ({
            message: issue.message,
            path: issue.path.map(String).join('.'),
        }));

        if (path === 'method') {
            return rpcAppError(
                c,
                result.data?.id ?? null,
                RPC_APP_ERRORS.methodNotAllowedForRoute,
                details,
            );
        }

        if (path === 'jsonrpc') {
            return rpcAppError(
                c,
                result.data?.id ?? null,
                RPC_APP_ERRORS.invalidJsonrpcVersion,
                details,
            );
        }

        if (path === 'params' || path.startsWith('params.')) {
            return rpcAppError(
                c,
                result.data?.id ?? null,
                invalidParams(path === 'params' ? undefined : path),
                details,
            );
        }

        return rpcAppError(c, result.data?.id ?? null, RPC_APP_ERRORS.invalidRequest, details);
    }
}

// ---------------------------------------------------------------------------
// Route schemas
// ---------------------------------------------------------------------------

/** Begin passkey registration — client provides the user identifier. */
export const userRegisterOptionsSchema = rpcEnvelope(
    'knot_userRegisterOptions',
    z.object({
        userId: z.string().min(1),
    }),
);

/** Complete registration — passkey credential + App Attest attestation. */
export const userRegisterVerifySchema = rpcEnvelope(
    'knot_userRegisterVerify',
    z.object({
        appAttestKeyId: z.string().min(1),
        attestation: z.string().min(1),
        challengeId: z.string().min(1),
        credential: credentialSchema,
    }),
);

/** Begin passkey authentication — client provides the stored credential id. */
export const userLoginOptionsSchema = rpcEnvelope(
    'knot_userLoginOptions',
    z.object({
        credentialId: z.string().min(1),
    }),
);

/** Complete login — passkey response + App Attest assertion. */
export const userLoginVerifySchema = rpcEnvelope(
    'knot_userLoginVerify',
    z.object({
        appAttestAssertion: z.string().min(1),
        appAttestKeyId: z.string().min(1),
        challengeId: z.string().min(1),
        response: authResponseSchema,
    }),
);

/** Revoke the caller's own session. Params are intentionally empty. */
export const userLogoutSchema = rpcEnvelope('knot_userLogout', z.object({}).loose());

/** Return supported chains, optionally filtered by environment. */
export const supportedChainsSchema = rpcEnvelope(
    'knot_supportedChains',
    z.object({
        environment: z.enum(['mainnet', 'testnet']).optional(),
    }),
);

export const relaySubmitSchema = rpcEnvelope(
    'knot_relaySubmit',
    z.discriminatedUnion('kind', [
        z.object({
            chainId: z.number().int(),
            kind: z.literal('single'),
            request: z.tuple([rpcUserOperationSchema, addressSchema]),
        }),
        z.object({
            chainId: z.number().int(),
            fillId: bytesSchema,
            kind: z.literal('plan'),
            request: z.tuple([
                z
                    .object({
                        background: z.array(rpcUserOperationSchema),
                        deferred: rpcUserOperationSchema,
                        immediate: rpcUserOperationSchema.optional(),
                    })
                    .strict()
                    .refine(
                        ({ background, deferred, immediate }) =>
                            background.length > 0 && deferred !== undefined,
                        {
                            message: 'Plan must include background and deferred user operations.',
                            path: ['background'],
                        },
                    ),
                addressSchema,
            ]),
        }),
    ]),
);

/** Issue a signed direct-upload URL for an image. */
export const imageUploadOptionsSchema = rpcEnvelope(
    'knot_imageUploadOptions',
    z.object({
        byteLength: z.number().int().positive(),
        contentType: z.string().min(1).startsWith('image/'),
        fileName: z
            .string()
            .min(1)
            .max(120)
            .regex(/^[a-zA-Z0-9._-]+$/),
        purpose: z.literal('avatar'),
    }),
);

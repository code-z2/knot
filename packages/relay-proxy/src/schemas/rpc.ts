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
import { MAINNET_CHAIN_IDS, MAINNET_CHAIN_IDZ, TESTNET_CHAIN_IDS, TESTNET_CHAIN_IDZ } from '@/constants';
import { RPC_APP_ERRORS, invalidParams } from '@/errors';
import type { RpcId } from '@/types';
import { rpcAppError } from '@/utils';
import type { Context } from 'hono';
import type { Address, Hex } from 'viem';
import { Authentication, Registration } from 'webauthx/server';
import { z } from 'zod';

const addressSchema = z.custom<Address>((value) => {
    return typeof value === 'string' && /^0x[a-fA-F0-9]{40}$/.test(value);
});
const hexValueSchema = z.custom<Hex>((value) => {
    return typeof value === 'string' && /^0x[a-fA-F0-9]+$/.test(value);
});
const bytesSchema = z.custom<Hex>((value) => {
    return typeof value === 'string' && /^0x[a-fA-F0-9]*$/.test(value);
});

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
    publicKey: z.custom<Hex>(),
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
        authenticatorData: z.custom<Hex>(),
        challengeIndex: z.number().optional(),
        clientDataJSON: z.string().min(1),
        typeIndex: z.number().optional(),
        userVerificationRequired: z.boolean().optional(),
    }),
    signature: z.custom<Hex>(),
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

/**
 * Strict schema for ERC-4337 UserOperations targeted at Gelato's sponsored bundler.
 *
 * ## Sponsored-Only Enforcement
 *
 * This proxy is exclusively for sponsored traffic. Following Gelato's Gas Tank architecture,
 * sponsored transactions must defer settlement until post-execution instead of pre-paying
 * via the EntryPoint. Therefore, this schema strictly requires:
 * - `maxFeePerGas: "0x0"`
 * - `maxPriorityFeePerGas: "0x0"`
 *
 * If a client sends a payload attempting to pre-pay fees (non-zero limits), it is rejected
 * at the Zod layer natively.
 */
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
        const issues = 'error' in result && result.error instanceof z.ZodError ? result.error.issues : [];
        const firstIssue = issues[0];
        const path = firstIssue ? firstIssue.path.map(String).join('.') : '';
        const details = issues.map((issue) => ({
            message: issue.message,
            path: issue.path.map(String).join('.'),
        }));

        if (path === 'method') {
            return rpcAppError(c, result.data?.id ?? null, RPC_APP_ERRORS.methodNotAllowedForRoute, details);
        }

        if (path === 'jsonrpc') {
            return rpcAppError(c, result.data?.id ?? null, RPC_APP_ERRORS.invalidJsonrpcVersion, details);
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
        userId: addressSchema,
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

export const gasStatusSchema = rpcEnvelope(
    'knot_gasStatus',
    z
        .object({
            environment: z.enum(['mainnet', 'testnet']).optional(),
        })
        .strict(),
);

export const gasHistorySchema = rpcEnvelope(
    'knot_gasHistory',
    z.object({
        window: z.enum(['1y', '3m', '6m']).optional(),
    }),
);

export const gasOverdraftUpdateSchema = rpcEnvelope(
    'knot_gasOverdraftUpdate',
    z.object({
        action: z.enum(['disable', 'enable']),
    }),
);

export const gasWithdrawSchema = rpcEnvelope(
    'knot_gasWithdraw',
    z
        .object({
            environment: z.enum(['mainnet', 'testnet']).optional(),
            deadline: z.number().int().positive(),
            to: addressSchema,
        })
        .strict(),
);

export const faucetRequestSchema = rpcEnvelope('knot_faucetRequest', z.object({}).strict());

/**
 * Extends the baseline UserOperation payload with proxy-specific routing metadata.
 *
 * The `strategy` dictates how and when the payload is executed:
 * - `immediate`: Executed synchronously, blocks the response until broadcast.
 * - `background`: Executed asynchronously in parallel, does not block response.
 * - `deferred`: Stored in a queue (KV) with a TTL, executed later in response to an orchestration event.
 */
const relayOperationSchema = rpcUserOperationSchema.extend({
    strategy: z.enum(['immediate', 'background', 'deferred']),
    chainId: z.coerce.number().pipe(z.union([MAINNET_CHAIN_IDZ, TESTNET_CHAIN_IDZ])),
});

/**
 * Schema for the array-based, rooted multi-step execution payload.
 *
 * ## Refinements
 *
 * This schema enforces rigorous structural and business logic through `.superRefine`:
 * 1. **Network Isolation**: All operations in the array must exclusively target Testnet chains or Mainnet chains. Mixing environments strictly fails validation.
 * 2. **Chain Uniqueness**: The proxy does not allow dispatching multiple ops to the same chain in a single payload.
 * 3. **Strategy Cardinality**:
 *    - For normal usage (`fillId` absent), there must be exactly 1 `immediate` operation and nothing else.
 *    - For plans (`fillId` present), there must be exactly 1 `deferred`, at least 1 `background`, and at most 1 `immediate` operation.
 */
const relaySubmitParamsSchema = z
    .object({
        fillId: bytesSchema.optional(),
        request: z.tuple([z.array(relayOperationSchema), addressSchema]),
    })
    .strict()
    .superRefine((data, ctx) => {
        const ops = data.request[0];

        let immediateCount = 0;
        let backgroundCount = 0;
        let deferredCount = 0;

        let hasDuplicateChainId = false;

        let hasMainnet = false;
        let hasTestnet = false;

        const uniqueChainIds = new Set<number>();

        for (const op of ops) {
            if (op.strategy === 'immediate') immediateCount++;
            else if (op.strategy === 'background') backgroundCount++;
            else if (op.strategy === 'deferred') deferredCount++;

            if (uniqueChainIds.has(op.chainId)) {
                hasDuplicateChainId = true;
            }
            uniqueChainIds.add(op.chainId);

            if ((MAINNET_CHAIN_IDS as readonly number[]).includes(op.chainId)) hasMainnet = true;
            if ((TESTNET_CHAIN_IDS as readonly number[]).includes(op.chainId)) hasTestnet = true;
        }

        if (hasDuplicateChainId) {
            ctx.addIssue({
                code: 'custom',
                message: 'Relay operations must target unique chain IDs.',
                path: ['request', 0],
            });
        }

        if (hasMainnet && hasTestnet) {
            ctx.addIssue({
                code: 'custom',
                message:
                    'All operations in a request must target either entirely mainnet chains or entirely testnet chains. You cannot mix environments.',
                path: ['request', 0],
            });
        }

        if (data.fillId) {
            if (immediateCount > 1 || deferredCount !== 1 || backgroundCount < 1) {
                ctx.addIssue({
                    code: 'custom',
                    message:
                        'Plans must contain exactly 1 deferred, at least 1 background, and at most 1 immediate operation.',
                    path: ['request', 0],
                });
            }
        } else if (ops.length !== 1 || immediateCount !== 1) {
            ctx.addIssue({
                code: 'custom',
                message: 'Single operations must contain exactly one immediate step.',
                path: ['request', 0],
            });
        }
    });

/**
 * The unified JSON-RPC 2.0 envelope schema for incoming `knot_relaySubmit` requests.
 *
 * This is the entry point for validation. It guarantees structural correctness
 * before the proxy does any active computation, caching, or middleware evaluation.
 */
export const relaySubmitSchema = rpcEnvelope('knot_relaySubmit', relaySubmitParamsSchema);

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

export type RelaySubmitInput = {
    out: {
        json: z.output<typeof relaySubmitSchema>;
    };
};

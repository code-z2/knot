import type { RpcAppErrorDefinition } from '@/types';

export const RPC_APP_ERRORS = {
    bundlerNotConfigured: {
        code: -32000,
        reason: 'bundler_not_configured',
        status: 500,
    },
    gasProviderUnsupported: {
        code: -32000,
        reason: 'unsupported_gas_provider',
        status: 400,
    },
    challengeNotFound: {
        code: -32000,
        reason: 'challenge_not_found',
        status: 400,
    },
    overdraftLocked: {
        code: -32000,
        reason: 'overdraft_locked',
        status: 400,
    },
    insufficientGasHeadroom: {
        code: -32000,
        reason: 'insufficient_gas_headroom',
        status: 400,
    },
    overdraftNotEligible: {
        code: -32000,
        reason: 'overdraft_not_eligible',
        status: 400,
    },
    pendingDebitOutstanding: {
        code: -32000,
        reason: 'pending_debit_outstanding',
        status: 400,
    },
    fileTooLarge: {
        code: -32000,
        reason: 'file_too_large',
        status: 400,
    },
    invalidJsonrpcVersion: {
        code: -32600,
        reason: 'invalid_jsonrpc_version',
        status: 400,
    },
    invalidRequest: {
        code: -32600,
        reason: 'invalid_request',
        status: 400,
    },
    methodNotAllowedForRoute: {
        code: -32601,
        reason: 'method_not_allowed_for_route',
        status: 400,
    },
    unauthorized: {
        code: -32001,
        reason: 'unauthorized',
        status: 401,
    },
    uploadUnavailable: {
        code: -32000,
        reason: 'upload_unavailable',
        status: 500,
    },
    userAlreadyExists: {
        code: -32000,
        reason: 'user_already_exists',
        status: 400,
    },
    userNotFound: {
        code: -32000,
        reason: 'user_not_found',
        status: 400,
    },
    verificationFailed: {
        code: -32001,
        reason: 'verification_failed',
        status: 401,
    },
} as const satisfies Record<string, RpcAppErrorDefinition>;

export function invalidParams(path?: string): RpcAppErrorDefinition {
    return {
        code: -32602,
        reason: path ? `invalid_params:${path}` : 'invalid_params',
        status: 400,
    };
}

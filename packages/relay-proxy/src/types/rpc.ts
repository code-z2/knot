import { SUPPORTED_RPC_METHODS } from '@/constants';
import type { RpcErrorDetail } from './error';

export type RpcId = string | number | null;

export type RpcVersion = '2.0';

/**
 * Route-scoped RPC methods accepted by the current relay-proxy surface.
 */
export type RpcMethod = (typeof SUPPORTED_RPC_METHODS)[number];

/**
 * Standard request envelope shared by every public route.
 */
export type RpcEnvelope<Method extends RpcMethod, Params> = {
    id: RpcId;
    jsonrpc: RpcVersion;
    method: Method;
    params: Params;
};

/**
 * Success envelope returned by route handlers.
 */
export type RpcSuccess<Result> = {
    id: RpcId;
    jsonrpc: RpcVersion;
    result: Result;
};

/**
 * Error envelope returned by route handlers.
 */
export type RpcFailure = {
    id: RpcId;
    jsonrpc: RpcVersion;
    error: {
        code: number;
        details?: RpcErrorDetail[];
        message: string;
        reason?: string;
    };
};

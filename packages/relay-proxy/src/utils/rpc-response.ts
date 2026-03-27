import type { Context } from 'hono';

import type { RpcAppErrorDefinition, RpcErrorDetail, RpcFailure, RpcId, RpcSuccess } from '@/types';

export function rpcError(
    c: Context,
    id: RpcId,
    code: number,
    message: string,
    status: 400 | 401 | 500 = 400,
    details?: RpcErrorDetail[],
) {
    return c.json(
        {
            jsonrpc: '2.0',
            id,
            error: {
                code,
                ...(details ? { details } : {}),
                message,
            },
        } satisfies RpcFailure,
        status,
    );
}

export function rpcAppError(
    c: Context,
    id: RpcId,
    error: RpcAppErrorDefinition,
    details?: RpcErrorDetail[],
) {
    return c.json(
        {
            jsonrpc: '2.0',
            id,
            error: {
                code: error.code,
                ...(details ? { details } : {}),
                message: error.reason,
                reason: error.reason,
            },
        } satisfies RpcFailure,
        error.status,
    );
}

export function rpcResult<Result>(id: RpcId, result: Result) {
    return {
        jsonrpc: '2.0',
        id,
        result,
    } satisfies RpcSuccess<Result>;
}

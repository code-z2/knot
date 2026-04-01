import type { MiddlewareHandler } from 'hono';

import { invalidParams, RPC_APP_ERRORS } from '@/errors/catalog';
import type { AppBindings, ChainPolicyBody } from '@/types';
import {
    getChainConfig,
    getEntryPointFromRequest,
    isSupportedEntryPoint,
    parseJsonRecord,
    rpcAppError,
} from '@/utils';

export function chainPolicy(): MiddlewareHandler<AppBindings> {
    return async (c, next) => {
        const rawBody = await c.req.text();
        const parsed = parseJsonRecord<ChainPolicyBody>(rawBody);
        if (parsed === null || (parsed != null && parsed?.params?.chainId === undefined)) {
            return rpcAppError(c, null, RPC_APP_ERRORS.invalidRequest);
        }

        const { id: rpcId, params } = parsed;

        const chain = getChainConfig(params?.chainId);

        if (chain === null || !chain.enabled) {
            return rpcAppError(c, rpcId, invalidParams('params.chainId'));
        }

        const entryPoint = getEntryPointFromRequest(params?.request);

        if (entryPoint !== null && !isSupportedEntryPoint(chain, entryPoint)) {
            return rpcAppError(c, rpcId, invalidParams('params.request.1'));
        }

        c.set('chain', chain);
        await next();
    };
}

import { invalidParams } from '@/errors';
import type { AppBindings, RelaySingleParams, RelaySubmitParams, RpcId } from '@/types';
import { rpcAppError } from '@/utils';
import { Context } from 'hono';
import { RpcUserOperation } from 'viem/account-abstraction';

const getSenders = (params: RelaySubmitParams): Set<string> => {
    switch (params.kind) {
        case 'plan': {
            const [ops] = params.request;
            return new Set(
                [ops.immediate, ...ops.background, ops.deferred]
                    .filter((op): op is RpcUserOperation => op != null)
                    .map((op) => op.sender.toLowerCase()),
            );
        }
        case 'single':
        default: {
            const _exhaustive: RelaySingleParams = params;
            return new Set([_exhaustive.request[0].sender.toLowerCase()]);
        }
    }
};

export const validateRelaySender = async (
    _: unknown,
    c: Context<Omit<AppBindings, 'Bindings'>, '/relay'>,
) => {
    const body = await c.req.json<{ id: RpcId; params: RelaySubmitParams }>();
    const senders = getSenders(body.params);

    if (senders.size !== 1 || !senders.has(c.get('session').userId.toLowerCase())) {
        return rpcAppError(c, body.id, invalidParams('sender mismatch'));
    }

    return body;
};

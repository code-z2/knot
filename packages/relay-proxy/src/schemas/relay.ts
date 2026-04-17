import { invalidParams } from '@/errors';
import type { AppBindings, RelaySubmitParams } from '@/types';
import { rpcAppError } from '@/utils';
import { Context } from 'hono';
import { RelaySubmitInput } from './rpc';

const getSenders = (params: RelaySubmitParams): Set<string> => {
    const [operations] = params.request;

    return new Set(operations.map((operation) => operation.sender.toLowerCase()));
};

export const validateRelaySender = async (
    _: unknown,
    c: Context<Omit<AppBindings, 'Bindings'>, string, RelaySubmitInput>,
) => {
    const body = c.req.valid('json');
    const senders = getSenders(body.params);

    if (senders.size !== 1 || !senders.has(c.get('session').userId.toLowerCase())) {
        return rpcAppError(c, body.id, invalidParams('sender mismatch'));
    }

    return body;
};

import { invalidParams } from '@/errors';
import type { AppBindings } from '@/types';
import { rpcAppError } from '@/utils';
import { Context } from 'hono';
import { RelaySubmitInput } from './rpc';

export const validateRelaySender = async (
    _: unknown,
    c: Context<Omit<AppBindings, 'Bindings'>, string, RelaySubmitInput>,
) => {
    const body = c.req.valid('json');
    const [operations] = body.params.request;
    const senders = new Set(operations.map((operation) => operation.sender.toLowerCase()));

    if (senders.size !== 1 || !senders.has(c.get('session').userId.toLowerCase())) {
        return rpcAppError(c, body.id, invalidParams('sender mismatch'));
    }

    return body;
};

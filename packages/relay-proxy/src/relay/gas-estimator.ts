import type { StateOverride } from 'viem';

import { BadRequestError } from '../shared/errors';
import { createChainClient } from '../shared/chains';

import type { Env } from '../shared/types';
import type { RelayTransactionRequestModel } from './types';

/** Estimates gas for a relay transaction request using an Alchemy-backed RPC client. */
export async function estimateRelayRequestGas(
    chainId: number,
    request: RelayTransactionRequestModel,
    env: Env,
): Promise<bigint> {
    const client = createChainClient(chainId, env.ALCHEMY_NODE_API_KEY);
    const stateOverride = buildStateOverride(request);

    try {
        return await client.estimateGas({
            account: request.from,
            to: request.to,
            data: request.data,
            value: request.value ? BigInt(request.value) : 0n,
            authorizationList: request.authorizationList,
            stateOverride,
        });
    } catch (error) {
        const reason = error instanceof Error ? error.message : 'unknown gas estimation error';
        throw new BadRequestError(`Gas estimation failed for chain ${chainId}: ${reason}`);
    }
}

/** Builds EIP-7702 delegation state override for gas estimation. */
function buildStateOverride(request: RelayTransactionRequestModel): StateOverride | undefined {
    const delegateAddress = request.authorizationList?.[0]?.address;
    if (!delegateAddress) return undefined;

    const delegationCode = `0xef0100${delegateAddress.slice(2)}` as const;
    return [{ address: request.from, code: delegationCode }];
}

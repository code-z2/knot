import { decodeFunctionData, encodeAbiParameters, keccak256, type Address, type Hex } from 'viem';

import { EXECUTE_INTENT_ABI } from '../../shared/abis/accumulator';

/**
 * Derives a deterministic ID for a cross-chain fill intent by hashing core
 * immutables (salt, deadline, output requirements) from the `executeIntent` calldata.
 */
export function deriveFillId(calldata: Hex, owner: Address): Hex {
    const { args } = decodeFunctionData({
        abi: EXECUTE_INTENT_ABI,
        data: calldata,
    });

    const params = args[0];

    return keccak256(
        encodeAbiParameters(
            [
                { type: 'bytes32' }, // salt
                { type: 'address' }, // owner
                { type: 'uint32' }, // fillDeadline
                { type: 'uint256' }, // sumOutput
                { type: 'address' }, // outputToken
            ],
            [params.salt, owner, params.fillDeadline, params.sumOutput, params.outputToken],
        ),
    );
}

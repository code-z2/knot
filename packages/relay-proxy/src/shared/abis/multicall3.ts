/** Multicall3 is deployed at the same address on all major EVM chains. */
export const MULTICALL3_ADDRESS = '0xcA11bde05977b3631167028862bE2a173976CA11' as const;

/** Multicall3 tryAggregate — non-atomic batched execution. */
export const MULTICALL3_TRY_AGGREGATE_ABI = [
    {
        type: 'function',
        name: 'tryAggregate',
        stateMutability: 'payable',
        inputs: [
            { name: 'requireSuccess', type: 'bool' },
            {
                name: 'calls',
                type: 'tuple[]',
                components: [
                    { name: 'target', type: 'address' },
                    { name: 'callData', type: 'bytes' },
                ],
            },
        ],
        outputs: [
            {
                name: 'returnData',
                type: 'tuple[]',
                components: [
                    { name: 'success', type: 'bool' },
                    { name: 'returnData', type: 'bytes' },
                ],
            },
        ],
    },
] as const;

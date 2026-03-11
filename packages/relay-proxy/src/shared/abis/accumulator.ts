import { parseAbiItem } from 'viem';

/** FillReady event emitted by Accumulator.sol upon successful bridge completion. */
export const FILL_READY_EVENT = parseAbiItem(
    'event FillReady(bytes32 indexed fillId, uint256 totalReceived, uint256 sumOutput)',
);

/** ABI for Accumulator.executeIntent — used to decode calldata for fill ID derivation. */
export const EXECUTE_INTENT_ABI = [
    {
        type: 'function',
        name: 'executeIntent',
        stateMutability: 'nonpayable',
        inputs: [
            {
                name: 'params',
                type: 'tuple',
                components: [
                    { name: 'salt', type: 'bytes32' },
                    { name: 'fillDeadline', type: 'uint32' },
                    { name: 'sumOutput', type: 'uint256' },
                    { name: 'outputToken', type: 'address' },
                    { name: 'finalMinOutput', type: 'uint256' },
                    { name: 'finalOutputToken', type: 'address' },
                    { name: 'recipient', type: 'address' },
                    { name: 'destinationCaller', type: 'address' },
                    {
                        name: 'destCalls',
                        type: 'tuple[]',
                        components: [
                            { name: 'target', type: 'address' },
                            { name: 'value', type: 'uint256' },
                            { name: 'data', type: 'bytes' },
                        ],
                    },
                ],
            },
            { name: 'merkleProof', type: 'bytes32[]' },
            { name: 'signature', type: 'bytes' },
        ],
        outputs: [],
    },
] as const;

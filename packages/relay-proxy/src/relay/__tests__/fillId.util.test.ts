import { describe, expect, it } from 'vitest';
import { encodeFunctionData, type Address } from 'viem';

import { deriveFillId } from '../utils/fillId';
import { EXECUTE_INTENT_ABI } from '../../shared/abis/accumulator';

describe('deriveFillId', () => {
    const mockOwner: Address = '0x1111111111111111111111111111111111111111';

    const MOCK_PARAMS = {
        salt: '0x2222222222222222222222222222222222222222222222222222222222222222' as const,
        fillDeadline: 1234567890,
        sumOutput: 1000000n,
        outputToken: '0x3333333333333333333333333333333333333333' as const,
        finalMinOutput: 500000n,
        finalOutputToken: '0x4444444444444444444444444444444444444444' as const,
        recipient: '0x5555555555555555555555555555555555555555' as const,
        destinationCaller: '0x6666666666666666666666666666666666666666' as const,
        destCalls: [],
    };

    const calldata1 = encodeFunctionData({
        abi: EXECUTE_INTENT_ABI,
        functionName: 'executeIntent',
        args: [MOCK_PARAMS, [], '0x'],
    });

    const calldata2 = encodeFunctionData({
        abi: EXECUTE_INTENT_ABI,
        functionName: 'executeIntent',
        args: [
            {
                ...MOCK_PARAMS,
                // Changing a field NOT part of the hash (merkle/destCalls aren't part of core intent identity)
                finalMinOutput: 999999n,
            },
            [],
            '0x',
        ],
    });

    const calldata3 = encodeFunctionData({
        abi: EXECUTE_INTENT_ABI,
        functionName: 'executeIntent',
        args: [
            {
                ...MOCK_PARAMS,
                // Changing a field THAT IS part of the hash
                sumOutput: 2000000n,
            },
            [],
            '0x',
        ],
    });

    it('produces deterministic hashes for identical inputs', () => {
        const hash1 = deriveFillId(calldata1, mockOwner);
        const hash2 = deriveFillId(calldata1, mockOwner);
        expect(hash1).toBe(hash2);
    });

    it('ignores non-core parameter changes (e.g. finalMinOutput)', () => {
        const hash1 = deriveFillId(calldata1, mockOwner);
        const hash2 = deriveFillId(calldata2, mockOwner);
        expect(hash1).toBe(hash2);
    });

    it('produces different hashes when core parameters change', () => {
        const hash1 = deriveFillId(calldata1, mockOwner);
        const hash3 = deriveFillId(calldata3, mockOwner);
        expect(hash1).not.toBe(hash3);
    });

    it('produces different hashes for different owners', () => {
        const hash1 = deriveFillId(calldata1, mockOwner);
        const hash4 = deriveFillId(calldata1, '0x9999999999999999999999999999999999999999');
        expect(hash1).not.toBe(hash4);
    });
});

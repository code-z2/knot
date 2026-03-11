import { describe, expect, it } from 'vitest';

import { BadRequestError } from '../../shared/errors';
import { parseSubmitRequest } from '../api/relay.parser';

describe('parseSubmitRequest', () => {
    it('parses a valid raw JSON request successfully', () => {
        const validRaw = JSON.stringify({
            account: '0x1111111111111111111111111111111111111111',
            supportMode: 'LIMITED_MAINNET',
            immediateTxs: [],
            backgroundTxs: [],
            deferredTxs: [
                {
                    chainId: 11155111,
                    request: {
                        from: '0x1111111111111111111111111111111111111111',
                        to: '0x2222222222222222222222222222222222222222',
                        data: '0xdeadbeef',
                    },
                },
            ],
            paymentOptions: [],
        });

        const parsed = parseSubmitRequest(validRaw);
        expect(parsed.account).toBe('0x1111111111111111111111111111111111111111');
        expect(parsed.supportMode).toBe('LIMITED_MAINNET');
        expect(parsed.deferredTxs.length).toBe(1);
        expect(parsed.deferredTxs[0].chainId).toBe(11155111);
        expect(parsed.deferredTxs[0].request.data).toBe('0xdeadbeef');
    });

    it('throws BadRequestError on invalid JSON', () => {
        expect(() => parseSubmitRequest('{ bad_json: true }')).toThrowError(BadRequestError);
    });

    it('throws BadRequestError on missing fields', () => {
        const badRaw = JSON.stringify({
            // Missing 'account'
            supportMode: 'LIMITED_MAINNET',
            immediateTxs: [],
            backgroundTxs: [],
            deferredTxs: [],
        });

        expect(() => parseSubmitRequest(badRaw)).toThrowError(BadRequestError);
    });

    it('throws BadRequestError on invalid chainId types', () => {
        const badRaw = JSON.stringify({
            account: '0x1111111111111111111111111111111111111111',
            supportMode: 'LIMITED_MAINNET',
            immediateTxs: [
                {
                    chainId: 'not_a_number', // Invalid
                    request: {
                        from: '0x1111111111111111111111111111111111111111',
                        to: '0x2222222222222222222222222222222222222222',
                        data: '0xdeadbeef',
                    },
                },
            ],
            backgroundTxs: [],
            deferredTxs: [],
        });

        expect(() => parseSubmitRequest(badRaw)).toThrowError(BadRequestError);
    });
});

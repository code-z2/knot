import { describe, expect, it } from 'vitest';
import { getAddress } from 'viem';

import { BadRequestError } from '../errors';
import {
    assertAddress,
    assertHex,
    assertObject,
    assertPositiveInteger,
    assertSupportMode,
    assertUnsignedInteger,
    formatNativeToken,
    normalizeAddress,
    parseBoundedInteger,
    parseUsdToWei,
} from '../validation';

// ---------------------------------------------------------------------------
// assertAddress
// ---------------------------------------------------------------------------

describe('assertAddress', () => {
    const VALID = '0x1111111111111111111111111111111111111111';

    it('returns checksummed address for valid lowercase input', () => {
        expect(assertAddress(VALID, 'addr')).toBe(getAddress(VALID));
    });

    it('trims whitespace', () => {
        expect(assertAddress(`  ${VALID}  `, 'addr')).toBe(getAddress(VALID));
    });

    it('accepts mixed-case addresses', () => {
        const mixed = '0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B';
        expect(assertAddress(mixed, 'addr')).toBe(getAddress(mixed));
    });

    it('throws on non-string', () => {
        expect(() => assertAddress(123, 'addr')).toThrow(BadRequestError);
        expect(() => assertAddress(null, 'addr')).toThrow(BadRequestError);
    });

    it('throws on invalid hex', () => {
        expect(() => assertAddress('0xZZZZ', 'addr')).toThrow(BadRequestError);
    });

    it('throws on short address', () => {
        expect(() => assertAddress('0x1234', 'addr')).toThrow(BadRequestError);
    });
});

// ---------------------------------------------------------------------------
// assertHex
// ---------------------------------------------------------------------------

describe('assertHex', () => {
    it('returns valid hex string', () => {
        expect(assertHex('0xdeadbeef', 'data')).toBe('0xdeadbeef');
    });

    it('accepts bare 0x', () => {
        expect(assertHex('0x', 'data')).toBe('0x');
    });

    it('trims whitespace', () => {
        expect(assertHex('  0xaa  ', 'data')).toBe('0xaa');
    });

    it('throws on non-hex string', () => {
        expect(() => assertHex('hello', 'data')).toThrow(BadRequestError);
    });

    it('throws on non-string', () => {
        expect(() => assertHex(42, 'data')).toThrow(BadRequestError);
    });
});

// ---------------------------------------------------------------------------
// assertObject
// ---------------------------------------------------------------------------

describe('assertObject', () => {
    it('returns plain objects', () => {
        const obj = { a: 1 };
        expect(assertObject(obj, 'body')).toBe(obj);
    });

    it('throws on null', () => {
        expect(() => assertObject(null, 'body')).toThrow(BadRequestError);
    });

    it('throws on arrays', () => {
        expect(() => assertObject([1, 2], 'body')).toThrow(BadRequestError);
    });

    it('throws on primitives', () => {
        expect(() => assertObject('string', 'body')).toThrow(BadRequestError);
        expect(() => assertObject(42, 'body')).toThrow(BadRequestError);
    });
});

// ---------------------------------------------------------------------------
// assertSupportMode
// ---------------------------------------------------------------------------

describe('assertSupportMode', () => {
    it.each(['LIMITED_TESTNET', 'LIMITED_MAINNET', 'FULL_MAINNET'])('accepts %s', (mode) => {
        expect(assertSupportMode(mode, 'mode')).toBe(mode);
    });

    it('trims whitespace', () => {
        expect(assertSupportMode('  LIMITED_TESTNET  ', 'mode')).toBe('LIMITED_TESTNET');
    });

    it('throws on invalid mode', () => {
        expect(() => assertSupportMode('INVALID', 'mode')).toThrow(BadRequestError);
    });

    it('throws on non-string', () => {
        expect(() => assertSupportMode(42, 'mode')).toThrow(BadRequestError);
    });
});

// ---------------------------------------------------------------------------
// assertPositiveInteger / assertUnsignedInteger
// ---------------------------------------------------------------------------

describe('assertUnsignedInteger', () => {
    it('accepts zero', () => {
        expect(assertUnsignedInteger(0, 'n')).toBe(0);
    });

    it('accepts positive numbers', () => {
        expect(assertUnsignedInteger(42, 'n')).toBe(42);
    });

    it('accepts numeric strings', () => {
        expect(assertUnsignedInteger('100', 'n')).toBe(100);
    });

    it('throws on negative numbers', () => {
        expect(() => assertUnsignedInteger(-1, 'n')).toThrow(BadRequestError);
    });

    it('throws on floats', () => {
        expect(() => assertUnsignedInteger(1.5, 'n')).toThrow(BadRequestError);
    });

    it('throws on non-numeric strings', () => {
        expect(() => assertUnsignedInteger('abc', 'n')).toThrow(BadRequestError);
    });

    it('throws on unsafe integers', () => {
        expect(() => assertUnsignedInteger(Number.MAX_SAFE_INTEGER + 1, 'n')).toThrow(
            BadRequestError,
        );
    });
});

describe('assertPositiveInteger', () => {
    it('accepts positive', () => {
        expect(assertPositiveInteger(1, 'n')).toBe(1);
    });

    it('throws on zero', () => {
        expect(() => assertPositiveInteger(0, 'n')).toThrow(BadRequestError);
    });
});

// ---------------------------------------------------------------------------
// normalizeAddress
// ---------------------------------------------------------------------------

describe('normalizeAddress', () => {
    const RAW = '0xAb5801a7D398351b8bE11C439e05C5B3259aeC9B';

    it('returns lowercased checksummed address', () => {
        const result = normalizeAddress(RAW);
        expect(result).toBe(getAddress(RAW).toLowerCase());
    });

    it('throws on invalid address', () => {
        expect(() => normalizeAddress('not_an_address')).toThrow(BadRequestError);
    });
});

// ---------------------------------------------------------------------------
// parseBoundedInteger
// ---------------------------------------------------------------------------

describe('parseBoundedInteger', () => {
    it('returns parsed value within bounds', () => {
        expect(parseBoundedInteger('50', 0, 100, 10)).toBe(50);
    });

    it('floors to integer', () => {
        expect(parseBoundedInteger('7.9', 0, 100, 10)).toBe(7);
    });

    it('returns fallback below min', () => {
        expect(parseBoundedInteger('-5', 0, 100, 10)).toBe(10);
    });

    it('returns fallback above max', () => {
        expect(parseBoundedInteger('200', 0, 100, 10)).toBe(10);
    });

    it('returns fallback for non-numeric', () => {
        expect(parseBoundedInteger('abc', 0, 100, 10)).toBe(10);
    });
});

// ---------------------------------------------------------------------------
// formatNativeToken
// ---------------------------------------------------------------------------

describe('formatNativeToken', () => {
    it('formats whole ETH', () => {
        expect(formatNativeToken(1_000_000_000_000_000_000n)).toBe('1');
    });

    it('formats fractional ETH', () => {
        expect(formatNativeToken(500_000_000_000_000_000n)).toBe('0.5');
    });

    it('strips trailing zeros', () => {
        expect(formatNativeToken(100_000_000_000_000_000n)).toBe('0.1');
    });

    it('formats zero', () => {
        expect(formatNativeToken(0n)).toBe('0');
    });

    it('formats negative', () => {
        const result = formatNativeToken(-2_000_000_000_000_000_000n);
        expect(result).toBe('-2');
    });
});

// ---------------------------------------------------------------------------
// parseUsdToWei
// ---------------------------------------------------------------------------

describe('parseUsdToWei', () => {
    it('parses positive value', () => {
        expect(parseUsdToWei('2')).toBe(2_000_000_000_000_000_000n);
    });

    it('parses negative value', () => {
        expect(parseUsdToWei('-2')).toBe(-2_000_000_000_000_000_000n);
    });

    it('parses fractional', () => {
        expect(parseUsdToWei('0.5')).toBe(500_000_000_000_000_000n);
    });

    it('returns 0n for empty string', () => {
        expect(parseUsdToWei('')).toBe(0n);
    });

    it('returns 0n for garbage', () => {
        expect(parseUsdToWei('not_a_number')).toBe(0n);
    });

    it('trims whitespace', () => {
        expect(parseUsdToWei('  1  ')).toBe(1_000_000_000_000_000_000n);
    });
});

/**
 * Pure validation and formatting functions.
 * Assertion functions throw BadRequestError on invalid input.
 */
import {
    formatEther,
    getAddress,
    isAddress,
    isHex,
    parseEther,
    type Address,
    type Hex,
} from 'viem';

import { SUPPORT_MODES } from './constants';
import { BadRequestError } from './errors';
import type { SupportMode } from './types';

// ---------------------------------------------------------------------------
// Assertion Functions (system boundary validators)
// ---------------------------------------------------------------------------

/** Validates and checksums an Ethereum address. */
export function assertAddress(value: unknown, label: string): Address {
    if (typeof value !== 'string') throw new BadRequestError(`${label} must be a string.`);
    const trimmed = value.trim().toLowerCase();
    if (!isAddress(trimmed)) throw new BadRequestError(`${label} is not a valid address.`);
    return getAddress(trimmed);
}

/** Validates a hex string (0x-prefixed). */
export function assertHex(value: unknown, label: string): Hex {
    if (typeof value !== 'string') throw new BadRequestError(`${label} must be a string.`);
    const trimmed = value.trim();
    if (!isHex(trimmed)) throw new BadRequestError(`${label} is not valid hex.`);
    return trimmed;
}

/** Validates a JSON object (non-null, non-array). */
export function assertObject(value: unknown, label: string): Record<string, unknown> {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
        throw new BadRequestError(`${label} must be an object.`);
    }
    return value as Record<string, unknown>;
}

/** Validates a SupportMode enum value. */
export function assertSupportMode(value: unknown, label: string): SupportMode {
    if (typeof value !== 'string') throw new BadRequestError(`${label} must be a string.`);
    const trimmed = value.trim();
    if (!SUPPORT_MODES.has(trimmed as SupportMode))
        throw new BadRequestError(`${label} is not a valid support mode.`);
    return trimmed as SupportMode;
}

/** Validates a positive integer (> 0). Accepts number or numeric string. */
export function assertPositiveInteger(value: unknown, label: string): number {
    const n = assertUnsignedInteger(value, label);
    if (n <= 0) throw new BadRequestError(`${label} must be positive.`);
    return n;
}

/** Validates an unsigned integer (>= 0). Accepts number or numeric string. */
export function assertUnsignedInteger(value: unknown, label: string): number {
    if (typeof value === 'number') {
        if (Number.isSafeInteger(value) && value >= 0) return value;
        throw new BadRequestError(`${label} must be a non-negative integer.`);
    }
    if (typeof value === 'string' && /^\d+$/.test(value.trim())) {
        const parsed = Number(value.trim());
        if (Number.isSafeInteger(parsed)) return parsed;
    }
    throw new BadRequestError(`${label} must be a non-negative integer.`);
}

// ---------------------------------------------------------------------------
// Address Normalization
// ---------------------------------------------------------------------------

/** Validates and lowercases an Ethereum address. Throws on invalid input. */
export function normalizeAddress(value: string): string {
    const trimmed = value.trim().toLowerCase();
    if (!isAddress(trimmed)) {
        throw new BadRequestError('Invalid account address.');
    }
    return getAddress(trimmed).toLowerCase();
}

// ---------------------------------------------------------------------------
// Number Parsing
// ---------------------------------------------------------------------------

/** Parses a bounded integer from a string, returning fallback if out of range. */
export function parseBoundedInteger(
    value: string,
    min: number,
    max: number,
    fallback: number,
): number {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) return fallback;
    const rounded = Math.floor(parsed);
    if (rounded < min || rounded > max) return fallback;
    return rounded;
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

/** Formats wei as ETH with trailing zeros removed. */
export function formatNativeToken(wei: bigint): string {
    const etherString = formatEther(wei);
    if (!etherString.includes('.')) return etherString;
    return etherString.replace(/\.?0+$/, '');
}

/** Parses an ETH-denominated string to wei. Supports negative values. Returns 0 on invalid input. */
export function parseUsdToWei(value: string): bigint {
    const trimmed = value.trim();
    if (!trimmed) return 0n;

    if (trimmed.startsWith('-')) {
        try {
            return -parseEther(trimmed.slice(1));
        } catch {
            return 0n;
        }
    }

    try {
        return parseEther(trimmed);
    } catch {
        return 0n;
    }
}

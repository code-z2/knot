/**
 * Fixed-point unsigned integer wrapper for USDC amounts.
 *
 * EVM token balances are raw `bigint` values with an implicit decimal
 * point (6 decimals for USDC). Passing raw `bigint` through the
 * codebase leads to formatting bugs and makes JSON serialization
 * non-trivial (JSON can't represent `bigint`).
 *
 * `uint` wraps a `bigint` with pre-computed `hex`, `formatted`, and
 * `toJSON` representations so every layer (DO storage, KV, HTTP
 * responses) gets the right encoding without ad-hoc conversions.
 *
 * Negative values are clamped to `0n` to prevent underflow from naive
 * subtraction (e.g., `balance - exposure` when exposure > balance).
 *
 * The companion `uint` namespace provides arithmetic helpers that
 * always return new `uint` values, keeping the type closed under
 * addition, subtraction, and comparison.
 *
 * @module
 */
import { fromHex, parseUnits, formatUnits, toHex, type Hex } from 'viem';

export type uint = {
    readonly decimals: number;
    readonly formatted: string;
    readonly hex: Hex;
    readonly toJSON: () => {
        decimals: number;
        formatted: string;
        hex: Hex;
        value: string;
    };
    readonly value: bigint;
};

export function uint(input: Hex | bigint, decimals: number = 6): uint {
    const value = typeof input === 'bigint' ? input : fromHex(input, 'bigint');
    const safe = value > 0n ? value : 0n;

    return {
        decimals: decimals,
        formatted: formatUnits(safe, decimals),
        hex: toHex(safe),
        toJSON() {
            return {
                decimals,
                formatted: formatUnits(safe, decimals),
                hex: toHex(safe),
                value: safe.toString(),
            };
        },
        value: safe,
    };
}

export namespace uint {
    export const zero = uint(0n);

    export function fromDecimal(input: string, decimals: number = 6): uint {
        return uint(parseUnits(input, decimals));
    }

    export function add(...amounts: readonly uint[]): uint {
        return uint(amounts.reduce((total, amount) => total + amount.value, 0n));
    }

    export function sub(left: uint, right: uint): uint {
        return uint(left.value - right.value);
    }

    export function min(left: uint, right: uint): uint {
        return left.value <= right.value ? left : right;
    }

    export function isZero(amount: uint): boolean {
        return amount.value === 0n;
    }

    export function gte(left: uint, right: uint): boolean {
        return left.value >= right.value;
    }

    export function lt(left: uint, right: uint): boolean {
        return left.value < right.value;
    }
}

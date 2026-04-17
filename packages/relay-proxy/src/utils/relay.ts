import { RelayOperation, UnwrappedRelayOperation, WrappedRelayOperation } from '@/types';

/**
 * Transforms the incoming raw flat array of `RelayOperation` into an enriched Array container.
 *
 * Instead of dealing with disparate structures, the proxy treats all operations as a strictly
 * ordered array. This utility attaches structural accessor properties (`.first`, `.last`)
 * directly onto the generic JavaScript array avoiding global prototype pollution.
 *
 * It also seamlessly injects the `.unwrap()` helper, a factory map returning exclusively the
 * underlying viem-compliant `RpcUserOperation` payload (stripping proxy-exclusive metadata
 * like `strategy` and `chainId`).
 *
 * This enables iteration over operations directly with robust typing while keeping payload
 * boundaries pristine for external services like Gelato or Viem.
 */
export function toRelayOperations(input: RelayOperation[]): Array<WrappedRelayOperation> & {
    first: UnwrappedRelayOperation;
    last: UnwrappedRelayOperation;
} {
    const mapped = input.map((v) =>
        Object.assign(v, {
            unwrap: () => {
                const { strategy, chainId, ...userOp } = v;
                return { chainId, userOp };
            },
        }),
    );

    return Object.assign(mapped, {
        first: mapped[0].unwrap(),
        last: mapped[mapped.length - 1].unwrap(),
    });
}

/**
 * Type-safe `Object.entries` that preserves the key and value types.
 *
 * Standard `Object.entries` widens keys to `string`. This version uses
 * a type assertion to return `[keyof T, T[keyof T]][]`, which is safe
 * when `T` has known literal keys (e.g., `RelayOperation` with
 * `SupportedChainId` keys).
 */
export function objectEntries<T extends object>(obj: T): [keyof T, T[keyof T]][] {
    return Object.entries(obj) as [keyof T, T[keyof T]][];
}

/**
 * Type-safe `Object.keys` that preserves key types.
 *
 * The generic `U` parameter allows callers to further narrow the key
 * type via `Extract`, which is useful when the object's `keyof` is a
 * union that includes string index signatures.
 */
export function objectKeys<T extends object, U>(value: T): readonly Extract<keyof T, U>[] {
    return Object.keys(value) as Extract<keyof T, U>[];
}

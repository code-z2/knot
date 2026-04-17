import type { CloudflareBindings, DOResponse } from '@/types';

const getStubUrl = <K extends 'GAS_TANK_DO' | 'FAUCET_DO'>(key: K, path: string) => {
    switch (key) {
        case 'GAS_TANK_DO':
            return new URL(`https://gas-tank.local${path}`);
        case 'FAUCET_DO':
            return new URL(`https://faucet.local${path}`);
        default:
            const _exhaustive: never = key;
            throw new Error(`Unknown DO key: ${_exhaustive}`);
    }
};

/**
 * Build a Durable Object RPC caller for the `GAS_TANK_DO` or `FAUCET_DO` binding.
 *
 * Returns a typed function that routes requests to the DO instance
 * keyed by `userId`. The DO uses a synthetic URL e.g. (`https://gas-tank/...`)
 * because Durable Objects require a `Request` but don’t actually serve
 * real HTTP — the URL is only used for internal routing.
 *
 * We could extend this by just doing `...extends 'GAS_TANK_DO' | 'FAUCET_DO'` to the generic K, but if CloudflareBindings does not expose the DOs as a Pick, we will be making bogus assumptions.
 */
export function doRequestHandler<K extends keyof Pick<CloudflareBindings, 'GAS_TANK_DO' | 'FAUCET_DO'>>(
    env: Pick<CloudflareBindings, K>,
    key: K,
) {
    const binding = env[key];

    return <Result>(userId: string, path: string, init?: RequestInit): Promise<Result> => {
        const id = binding.idFromName(userId);
        const stub = binding.get(id);

        const url = getStubUrl(key, path);
        url.searchParams.set('userId', userId);

        return stub
            .fetch(url, init)
            .then((r) => r.json<DOResponse<Result>>())
            .then((json) => {
                if (!json.ok) throw new Error(json.reason);
                return json.result;
            });
    };
}

export const withError = (reason: string): Response => {
    return Response.json({
        ok: false,
        reason,
    });
};

export const withResponse = <Result>(result: Result): Response => {
    return Response.json({
        ok: true,
        result,
    });
};

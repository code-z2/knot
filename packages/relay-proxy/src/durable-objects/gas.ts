import { createGasProfileStore } from '@/stores/gas';
import type { CloudflareBindings, GasProfileRecord } from '@/types';
import { uint, withError, withResponse } from '@/utils';
import { Hex } from 'viem';

/**
 * Per-user Durable Object that serializes gas-tank exposure mutations.
 *
 * In a concurrent relay scenario, two requests for the same user could
 * both read the same balance and both pass the headroom check, causing
 * over-allocation. The DO prevents this by providing single-writer
 * access per user: all exposure reads and writes are serialized through
 * the DO's `fetch` handler.
 *
 * ## Internal API
 *
 * | Method | Path                            | Purpose                                    |
 * |--------|---------------------------------|--------------------------------------------|
 * | GET    | `/`                             | Return current `pendingExposureUsdc`       |
 * | POST   | `/admit`                        | Headroom check + increment pending exposure|
 * | POST   | `/pending-exposure/increment`   | Raw increment (used by `/admit` fallthrough)|
 * | POST   | `/pending-exposure/decrement`   | Release pending exposure after settlement  |
 * | POST   | `/outstanding-debt/increment`   | Move fee from \"pending\" to \"owed\" in D1   |
 * | POST   | `/outstanding-debt/decrement`   | Reduce debt after on-chain collection      |
 *
 * Note: `/admit` intentionally falls through to `/pending-exposure/increment`
 * after the headroom check passes. This avoids duplicating the increment
 * logic but does mean the switch cases must remain adjacent.
 */
export class GasAccountDurableObject {
    private static readonly DO_KEY = 'gas-tank:do';

    constructor(
        private readonly ctx: DurableObjectState,
        private readonly env: Pick<CloudflareBindings, 'GAS_TANK_DB'>,
    ) {}

    private async getRecord(): Promise<Record<'pendingExposureUsdc', uint>> {
        const record = await this.ctx.storage.get<Record<'pendingExposureUsdc', Hex>>(GasAccountDurableObject.DO_KEY);
        return {
            pendingExposureUsdc: uint(record?.pendingExposureUsdc ?? uint.zero.hex),
        };
    }

    private getProfile(store: ReturnType<typeof createGasProfileStore>) {
        return async (userId: string): Promise<GasProfileRecord> => {
            return await store.getGasProfile(userId);
        };
    }

    async fetch(request: Request): Promise<Response> {
        try {
            const url = new URL(request.url);
            const userId = url.searchParams.get('userId');

            if (!userId) {
                return withError('gas_account_user_id_required');
            }

            if (request.method === 'GET' && url.pathname === '/') {
                const record = await this.getRecord();
                return withResponse({
                    pendingExposureUsdc: record.pendingExposureUsdc.hex,
                });
            }

            if (request.method !== 'POST') {
                return new Response('Not found', { status: 404 });
            }

            const body = await request.json();
            let amountUsdc: uint | null = null;

            const record = await this.getRecord();
            const store = createGasProfileStore(this.env);

            switch (url.pathname) {
                case '/admit': {
                    const { balance, quote } = body as Record<string, Hex>;
                    amountUsdc = uint(quote);

                    const gasProfile = await this.getProfile(store)(userId);
                    const overdraft = gasProfile.overdraftEnabled ? gasProfile.minimumAllowedUsdc : uint.zero;

                    const headroom = uint(
                        uint(balance).value +
                            overdraft.value -
                            gasProfile.outstandingDebtUsdc.value -
                            record.pendingExposureUsdc.value,
                    );

                    if (uint.lt(headroom, amountUsdc)) {
                        return withError('insufficient_gas_headroom');
                    }
                    // Fallthrough to increment pending exposure
                }
                case '/pending-exposure/increment': {
                    const copy = {
                        ...record,
                        pendingExposureUsdc: uint.add(record.pendingExposureUsdc, amountUsdc ?? uint(body as Hex)).hex,
                    };
                    await this.ctx.storage.put(GasAccountDurableObject.DO_KEY, copy);
                    return withResponse(copy);
                }
                case '/pending-exposure/decrement': {
                    const copy = {
                        ...record,
                        pendingExposureUsdc: uint.sub(record.pendingExposureUsdc, uint(body as Hex)).hex,
                    };
                    await this.ctx.storage.put(GasAccountDurableObject.DO_KEY, copy);
                    return withResponse(copy);
                }
                case '/outstanding-debt/increment': {
                    const gasProfile = await this.getProfile(store)(userId);
                    const nextOutstandingDebtUsdc = uint.add(gasProfile.outstandingDebtUsdc, uint(body as Hex));

                    await store.updateGasProfile({
                        ...gasProfile,
                        outstandingDebtUsdc: nextOutstandingDebtUsdc,
                        updatedAt: Date.now(),
                    });
                    return withResponse({
                        outstandingDebtUsdc: nextOutstandingDebtUsdc.hex,
                    });
                }
                case '/outstanding-debt/decrement': {
                    const gasProfile = await this.getProfile(store)(userId);
                    const nextOutstandingDebtUsdc = uint.sub(gasProfile.outstandingDebtUsdc, uint(body as Hex));

                    await store.updateGasProfile({
                        ...gasProfile,
                        outstandingDebtUsdc: nextOutstandingDebtUsdc,
                        updatedAt: Date.now(),
                    });
                    return withResponse({
                        outstandingDebtUsdc: nextOutstandingDebtUsdc.hex,
                    });
                }
                default:
                    console.error(`[gas-account] Unknown pathname: ${url.pathname}`);
                    return new Response('Not found', { status: 404 });
            }
        } catch (error) {
            const reason = error instanceof Error ? error.message : 'gas_account_unknown_error';
            return withError(reason);
        }
    }
}

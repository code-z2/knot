import { encodeFunctionData, erc20Abi, isAddress, parseEther, parseUnits, type Call, type Hex } from 'viem';

import { executeCalls } from '@/services/account';
import { createBundlerClient } from '@/services/bundler';
import { createFaucetStore } from '@/stores/faucet';
import type { CloudflareBindings, FaucetFundDOResult, FaucetRequestDOResult } from '@/types';
import { getTestnetChains, withError, withResponse } from '@/utils';

export class FaucetDurableObject {
    private static readonly DO_KEY = 'faucet:do';

    constructor(
        private readonly ctx: DurableObjectState,
        private readonly env: CloudflareBindings,
    ) {}

    async fetch(request: Request): Promise<Response> {
        const url = new URL(request.url);
        const userId = url.searchParams.get('userId');

        if (!userId || !isAddress(userId)) {
            return withError('faucet_user_id_required');
        }

        if (request.method !== 'POST') {
            return new Response('Not found', { status: 404 });
        }

        switch (url.pathname) {
            case '/request':
                const consumed = await createFaucetStore(this.env).consume(userId);

                if (!consumed) {
                    return withError('faucet_already_consumed');
                }

                try {
                    await this.env.FAUCET_QUEUE.send(userId);
                    return withResponse<FaucetRequestDOResult>({
                        accepted: true,
                        queued: true,
                    });
                } catch (error) {
                    console.error('[faucet] queue send failed', error);
                    return withError('faucet_queue_send_failed');
                }

            case '/fund':
                const funded = await this.ctx.storage.get<boolean>(FaucetDurableObject.DO_KEY);
                if (funded) {
                    return withResponse<FaucetFundDOResult>({
                        status: 'fulfilled',
                        hashes: {},
                    });
                }

                await this.ctx.storage.put(FaucetDurableObject.DO_KEY, true);
                const fundableChains = getTestnetChains().filter((chain) => chain.faucet.assets.length > 0);

                const hashes: Record<number, Hex> = {};
                const promises = fundableChains.map(async (chain) => {
                    const calls = chain.faucet.assets.map((asset) => {
                        const call: Call = {
                            to: userId,
                        };

                        switch (asset.kind) {
                            case 'native':
                                call.value = parseEther(asset.amount);
                                break;

                            default:
                                call.data = encodeFunctionData({
                                    abi: erc20Abi,
                                    args: [userId, parseUnits(asset.amount, 6)],
                                    functionName: 'transfer',
                                });
                                break;
                        }

                        return call;
                    });

                    if (calls.length > 0) {
                        const bundler = await createBundlerClient(this.env, chain, {});
                        const receipt = await executeCalls(bundler, calls);
                        hashes[chain.id] = receipt.userOpHash;
                    }
                });

                const results = await Promise.allSettled(promises);
                const partial = results.some((result) => result.status === 'rejected');

                return withResponse<FaucetFundDOResult>({
                    status: partial ? 'partial' : 'fulfilled',
                    hashes,
                });

            default:
                return new Response('Not found', { status: 404 });
        }
    }
}

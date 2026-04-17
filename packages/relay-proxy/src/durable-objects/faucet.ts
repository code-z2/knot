import { encodeFunctionData, erc20Abi, isAddress, parseEther, parseUnits, type Call, type Hex } from 'viem';

import { executeCalls } from '@/services/account';
import { createBundlerClient } from '@/services/bundler';
import { createFaucetStore } from '@/stores/faucet';
import type { CloudflareBindings } from '@/types';
import { getTestnetChains, objectKeys, withError, withResponse } from '@/utils';

export class FaucetDurableObject {
    constructor(
        private readonly _ctx: DurableObjectState,
        private readonly env: CloudflareBindings,
    ) {}

    async fetch(request: Request): Promise<Response> {
        const url = new URL(request.url);
        const userId = url.searchParams.get('userId');

        if (!userId || !isAddress(userId)) {
            return withError('faucet_user_id_required');
        }

        if (request.method !== 'POST' || url.pathname !== '/request') {
            return new Response('Not found', { status: 404 });
        }

        const consumed = await createFaucetStore(this.env).consume(userId);

        if (!consumed) {
            return withError('faucet_already_consumed');
        }

        const hashes: Record<number, Hex> = {};

        for (const chain of getTestnetChains()) {
            try {
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

                if (calls.length === 0) {
                    continue;
                }

                const bundler = await createBundlerClient(this.env, chain, {});
                const receipt = await executeCalls(bundler, calls);
                hashes[chain.id] = receipt.userOpHash;
            } catch (error) {
                console.error(`[faucet] funding failed on chain ${chain.id}`, error);
            }
        }

        return withResponse({
            funded: objectKeys(hashes).length > 0,
            hashes,
        });
    }
}

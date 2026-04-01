import {
    createBundlerClient as createBundlerClientBase,
    type RpcUserOperation,
} from 'viem/account-abstraction';

import type { BundlerConfig, CreateBundlerFactory, GelatoBundlerRpcSchema } from '@/types';
import { buildBundlerUrl, buildJsonRpcUrl } from '@/utils';
import { Address, createPublicClient, http, rpcSchema } from 'viem';

function createClient(config: BundlerConfig) {
    const { chain, bundlerApiKey, jsonRpcApiKey } = config;
    const url = buildJsonRpcUrl(chain.id, jsonRpcApiKey);

    const client = createPublicClient({
        chain,
        transport: http(url),
    });

    return createBundlerClientBase({
        chain,
        client,
        rpcSchema: rpcSchema<GelatoBundlerRpcSchema>(),
        transport: http(buildBundlerUrl(chain.id), {
            fetchOptions: {
                headers: {
                    'X-API-Key': bundlerApiKey,
                } satisfies HeadersInit,
            },
        }),
    }).extend((client) => {
        return {
            async getUserOperationQuote(userOperation: RpcUserOperation, entryPoint: Address) {
                return client.request({
                    method: 'gelato_getUserOperationQuote',
                    params: [userOperation, entryPoint, chain.gelato.quoteToken],
                });
            },
            async sendUserOperationSync(userOperation: RpcUserOperation, entryPoint: Address) {
                return client.request({
                    method: 'eth_sendUserOperationSync',
                    params: [userOperation, entryPoint],
                });
            },
            // pass through to the bundler
            async sendUserOperation(userOperation: RpcUserOperation, entryPoint: Address) {
                return client.request({
                    method: 'eth_sendUserOperation',
                    params: [userOperation, entryPoint],
                });
            },
        };
    });
}

export function createBundlerClient(
    config: BundlerConfig,
    factory: CreateBundlerFactory<ReturnType<typeof createClient>> = createClient,
) {
    return factory(config);
}

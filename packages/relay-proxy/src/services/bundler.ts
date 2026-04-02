import {
    createBundlerClient as createBundlerClientBase,
    type RpcUserOperation,
} from 'viem/account-abstraction';

import type {
    AppBindings,
    BundlerConfig,
    CreateAppOptions,
    GelatoBundlerRpcSchema,
    BundlerClient,
    SupportedChainConfig,
    CloudflareBindings,
    SendUserOperationBatchResult,
} from '@/types';
import { buildBundlerUrl, buildJsonRpcUrl } from '@/utils';
import { Address, createPublicClient, http, rpcSchema } from 'viem';

function createBundlerConfig(
    env: Pick<CloudflareBindings, 'BUNDLER_API_KEY' | 'JSON_RPC_API_KEY'>,
    chain: SupportedChainConfig,
): BundlerConfig {
    return {
        chain,
        bundlerApiKey: env.BUNDLER_API_KEY,
        jsonRpcApiKey: env.JSON_RPC_API_KEY,
    };
}

function createBundler(config: BundlerConfig): BundlerClient {
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
            // pass through to the bundler
            async sendUserOperation(userOperation: RpcUserOperation, entryPoint: Address) {
                return client.request({
                    method: 'eth_sendUserOperation',
                    params: [userOperation, entryPoint],
                });
            },
            async sendUserOperationBatch(userOperations: RpcUserOperation[], entryPoint: Address) {
                const results = await Promise.allSettled(
                    userOperations.map((userOperation) =>
                        client.request({
                            method: 'eth_sendUserOperation',
                            params: [userOperation, entryPoint],
                        }),
                    ),
                );

                return results.map((result, index) => {
                    const isSuccess = result.status === 'fulfilled';
                    return isSuccess
                        ? { index, ok: true, hash: result.value }
                        : { index, ok: false, error: result.reason };
                }) satisfies SendUserOperationBatchResult[];
            },
            async sendUserOperationSync(userOperation: RpcUserOperation, entryPoint: Address) {
                return client.request({
                    method: 'eth_sendUserOperationSync',
                    params: [userOperation, entryPoint],
                });
            },
        };
    });
}

/**
 * Returns the injected bundler client when tests provide one, otherwise creates
 * the Cloudflare-backed bundler client.
 */
export function createBundlerClient(
    env: Pick<AppBindings['Bindings'], 'BUNDLER_API_KEY' | 'JSON_RPC_API_KEY'>,
    chain: SupportedChainConfig,
    options: Pick<CreateAppOptions, 'bundler'>,
) {
    return options.bundler ?? createBundler(createBundlerConfig(env, chain));
}

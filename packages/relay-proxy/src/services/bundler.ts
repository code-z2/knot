/**
 * Bundler service — creates a viem `BundlerClient` extended with Gelato
 * and relay-specific RPC methods.
 *
 * ## Architecture
 *
 * Each `BundlerClient` wraps:
 * - A **public client** (Goldsky EVM RPC) used for on-chain reads.
 * - A **Knot account** (EIP-7702 smart account via `toKnotAccount`) that
 *   owns the server-side signing key. The account can batch-execute,
 *   sign UserOperations, and authorize EIP-7702 delegations.
 * - A **transport** pointed at Gelato’s bundler endpoint, which handles
 *   gas estimation, sponsorship, and UserOperation submission.
 *
 * The client is extended with methods that map directly to Gelato’s
 * non-standard RPC surface:
 *
 * | Method                     | RPC call                      | Purpose                                  |
 * |----------------------------|-------------------------------|------------------------------------------|
 * | `getUserOperationQuote`    | `gelato_getUserOperationQuote`| Pre-flight fee quote in the chain’s USDC |
 * | `sendUserOperation`        | `eth_sendUserOperation`       | Fire-and-forget submit                   |
 * | `sendUserOperationSync`    | `eth_sendUserOperationSync`   | Submit and wait for receipt              |
 * | `sendUserOperationBatch`   | N × `eth_sendUserOperation`   | Parallel submit with settled results     |
 * | `getRelayFeeQuote`         | `relayer_getFeeQuote`         | Gas-price quote for the relay fee token  |
 *
 * @module
 */
import { createBundlerClient as createBundlerClientBase, type RpcUserOperation } from 'viem/account-abstraction';

import type {
    AppBindings,
    BundlerClient,
    BundlerConfig,
    CreateAppOptions,
    GelatoBundlerRpcSchema,
    SendUserOperationBatchResult,
    SupportedChainConfig,
} from '@/types';
import { buildBundlerUrl, buildJsonRpcUrl } from '@/utils';
import { Address, createPublicClient, Hex, http, rpcSchema } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { toKnotAccount } from './account';

/**
 * Resolve secrets and environment bindings into a flat config object.
 *
 * Secrets (`BUNDLER_API_KEY`, `JSON_RPC_API_KEY`, `SERVER_KEY`) are fetched
 * from Cloudflare’s Secrets Store and awaited here so `createBundler` can
 * operate synchronously on the config values.
 */
async function createBundlerConfig(
    env: Parameters<typeof createBundlerClient>[0],
    chain: SupportedChainConfig,
): Promise<BundlerConfig> {
    const bundlerApiKey = await env.BUNDLER_API_KEY.get();
    const jsonRpcApiKey = await env.JSON_RPC_API_KEY.get();
    const serverKey = (await env.SERVER_KEY.get()) as Hex;
    const accountImplementation = env.ACCOUNT_IMPLEMENTATION;
    const accountInitParams = {
        spokePool: env.SPOKE_POOL,
        consumerHub: env.CONSUMER_HUB,
        validatorModule: env.MERKLE_VALIDATOR_MODULE,
        executorModule: env.CROSS_CHAIN_EXECUTOR_MODULE,
        accumulatorModule: env.ACCUMULATOR_MODULE,
        publicKey: {
            x: env.GX,
            y: env.GY,
        },
    };
    return {
        chain,
        bundlerApiKey,
        jsonRpcApiKey,
        serverKey,
        accountImplementation,
        accountInitParams,
    };
}

/**
 * Assemble a viem `BundlerClient` with Gelato extensions.
 *
 * This is the heavy constructor — it creates a public client, derives
 * the Knot account from the server private key, and builds the bundler
 * transport. The result is long-lived for the duration of the request
 * because `chainPolicy` middleware caches the returned promise.
 */
async function createBundler(config: BundlerConfig): Promise<BundlerClient> {
    const { chain, bundlerApiKey, jsonRpcApiKey, serverKey, accountImplementation, accountInitParams } = config;
    const url = buildJsonRpcUrl(chain.id, jsonRpcApiKey);

    const owner = privateKeyToAccount(serverKey);

    const client = createPublicClient({
        chain,
        transport: http(url),
    });

    const account = await toKnotAccount({
        client,
        owner,
        delegate: accountImplementation,
        initParams: accountInitParams,
    });

    return createBundlerClientBase({
        chain,
        client,
        account,
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
                        ? { index, ok: true, hash: result.value, chainId: chain.id }
                        : { index, ok: false, error: result.reason, chainId: chain.id };
                }) satisfies SendUserOperationBatchResult[];
            },
            async sendUserOperationSync(userOperation: RpcUserOperation, entryPoint: Address) {
                return client.request({
                    method: 'eth_sendUserOperationSync',
                    params: [userOperation, entryPoint],
                });
            },
            async getRelayFeeQuote(gas: string) {
                return client.request({
                    method: 'relayer_getFeeQuote',
                    params: {
                        chainId: chain.id.toString(),
                        gas,
                        token: chain.gelato.quoteToken,
                    },
                });
            },
        };
    });
}

/**
 * Returns the injected bundler client when tests provide one, otherwise creates
 * the Cloudflare-backed bundler client.
 */
export async function createBundlerClient(
    env: Pick<
        AppBindings['Bindings'],
        | 'BUNDLER_API_KEY'
        | 'JSON_RPC_API_KEY'
        | 'SERVER_KEY'
        | 'ACCOUNT_IMPLEMENTATION'
        | 'CROSS_CHAIN_EXECUTOR_MODULE'
        | 'ACCUMULATOR_MODULE'
        | 'MERKLE_VALIDATOR_MODULE'
        | 'SPOKE_POOL'
        | 'CONSUMER_HUB'
        | 'GX'
        | 'GY'
    >,
    chain: SupportedChainConfig,
    options: Pick<CreateAppOptions, 'bundler'>,
) {
    return options.bundler ?? createBundler(await createBundlerConfig(env, chain));
}

import {
    entryPoint09Abi,
    entryPoint09Address,
    formatUserOperationRequest,
    getUserOperationHash,
    SmartAccountImplementation,
    toSmartAccount,
} from 'viem/account-abstraction';

import { EIP7702_FACTORY, KNOT_ACCOUNT_ABI } from '@/constants';
import type { BundlerClient, ToKnotAccountParameters } from '@/types';
import {
    decodeKnotAccountExecution,
    encodeKnotAccountBatchExecution,
    encodeKnotAccountInitParams,
    encodeKnotAccountSingleExecution,
} from '@/utils';
import { Address, Call, PublicClient } from 'viem';
import { getChainId, getDelegation } from 'viem/actions';
import { getAction } from 'viem/utils';

/**
 * Create a viem SmartAccount adaptor for a Knot EIP-7702 account.
 *
 * Knot accounts use EIP-7702 delegation: the server-side EOA (`owner`)
 * delegates to a `delegate` implementation contract. On first use, the
 * factory data contains the `initialize()` calldata that installs the
 * validator, executor, and accumulator modules with their respective
 * configs (public key, spoke pool, consumer hub).
 *
 * This adaptor bridges viem's `SmartAccount` interface (which expects
 * `encodeCalls`, `getFactoryArgs`, `signUserOperation`, etc.) to the
 * Knot account's ABI. The result is a fully-typed `KnotAccount` that
 * the bundler client uses for transaction signing and UserOp formatting.
 *
 * @param params.client - Public client for on-chain reads (delegation check, chain ID).
 * @param params.owner - EOA that owns the account and signs operations.
 * @param params.delegate - Implementation contract address for EIP-7702.
 * @param params.initParams - Module configuration for first-time initialization.
 */
export function toKnotAccount(params: ToKnotAccountParameters) {
    const { client, owner, delegate, initParams } = params;

    let chainId: number;

    const getMemoizedChainId = async () => {
        if (chainId) return chainId;
        if (client.chain) return client.chain.id;
        chainId = await getAction(client, getChainId, 'getChainId')({});
        return chainId;
    };

    const isDeployed = async () => {
        const delegation = await getDelegation(client, { address: owner.address });
        return Boolean(delegation);
    };

    const getFactoryArgs = async () => {
        const hasCode = await isDeployed();
        if (hasCode) {
            return { factory: undefined, factoryData: undefined };
        }
        return {
            factory: EIP7702_FACTORY,
            factoryData: encodeKnotAccountInitParams(initParams),
        };
    };

    return toSmartAccount<
        SmartAccountImplementation<
            typeof entryPoint09Abi,
            '0.9',
            {
                abi: typeof KNOT_ACCOUNT_ABI;
                implementation: Address;
                publicClient: PublicClient;
            },
            true
        >
    >({
        client,
        entryPoint: {
            abi: entryPoint09Abi,
            address: entryPoint09Address,
            version: '0.9',
        },
        getFactoryArgs,
        extend: {
            abi: KNOT_ACCOUNT_ABI,
            implementation: delegate,
            publicClient: client,
        },
        authorization: {
            address: delegate,
            account: owner,
        },
        async getAddress() {
            return owner.address;
        },
        async encodeCalls(calls) {
            if (calls.length === 1) {
                return encodeKnotAccountSingleExecution(calls[0]!);
            }
            return encodeKnotAccountBatchExecution(calls);
        },
        async decodeCalls(data) {
            return decodeKnotAccountExecution(data);
        },

        async getStubSignature() {
            return '0xfffffffffffffffffffffffffffffff0000000000000000000000000000000007aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1c';
        },

        async sign(data) {
            return owner.sign(data);
        },
        signMessage: async (params) => {
            return owner.signMessage(params);
        },
        signTypedData: async (params) => {
            return owner.signTypedData(params);
        },

        async signUserOperation(userOperation) {
            const hash = getUserOperationHash({
                chainId: await getMemoizedChainId(),
                entryPointAddress: entryPoint09Address,
                entryPointVersion: '0.9',
                userOperation: {
                    ...userOperation,
                    sender: userOperation.sender ?? owner.address,
                    signature: '0x',
                },
            });

            return owner.sign({ hash });
        },
    });
}

export const executeCalls = async (bundler: BundlerClient, calls: readonly Call[]) => {
    const request = await bundler.prepareUserOperation({
        calls: [...calls],
        maxFeePerGas: 0n,
        maxPriorityFeePerGas: 0n,
        parameters: ['authorization', 'factory', 'gas', 'nonce', 'signature'],
    });

    const authorization = request.authorization
        ? {
              authorization: await bundler.account.authorization.account.signAuthorization({
                  address: request.authorization.address,
                  chainId: request.authorization.chainId,
                  nonce: request.authorization.nonce,
              }),
          }
        : {};

    const signature = await bundler.account.signUserOperation({
        ...request,
        ...authorization,
    });

    const operation = formatUserOperationRequest({
        ...request,
        ...authorization,
        signature,
    });

    const receipt = await bundler.sendUserOperationSync(operation, bundler.account.entryPoint.address);

    if (!receipt.success) {
        throw new Error('batch_submission_failed');
    }

    return receipt;
};

import { toKnotAccount } from '@/services/account';
import type { Address, Client, Hex, Transport } from 'viem';
import type { BundlerActions, RpcUserOperation, RpcUserOperationReceipt } from 'viem/account-abstraction';
import { KnotAccountInitParams } from './account';
import type { SupportedChainConfig, SupportedChainId } from './chain';

export type BundlerConfig = {
    chain: SupportedChainConfig;
    bundlerApiKey: string;
    jsonRpcApiKey: string;
    serverKey: Hex;
    accountImplementation: Address;
    accountInitParams: KnotAccountInitParams;
};

export type SendUserOperationBatchResult =
    | {
          chainId: SupportedChainId;
          ok: true;
          hash: Hex;
      }
    | {
          chainId: SupportedChainId;
          ok: false;
          error: unknown;
      };

export type KnotAccount = Awaited<ReturnType<typeof toKnotAccount>>;

export type BundlerClient = Client<Transport, SupportedChainConfig, KnotAccount> &
    Pick<BundlerActions<KnotAccount>, 'getUserOperationReceipt' | 'prepareUserOperation'> & {
        getUserOperationQuote: (
            userOperation: RpcUserOperation,
            entryPoint: Address,
        ) => Promise<GelatoUserOperationQuote>;
        sendUserOperation: (userOperation: RpcUserOperation, entryPoint: Address) => Promise<Hex>;
        sendUserOperationSync: (
            userOperation: RpcUserOperation,
            entryPoint: Address,
        ) => Promise<RpcUserOperationReceipt>;
        sendUserOperationBatch: (
            userOperations: RpcUserOperation[],
            entryPoint: Address,
        ) => Promise<SendUserOperationBatchResult[]>;
        getRelayFeeQuote: (gas: string) => Promise<RelayFeeQuote>;
    };

export type GelatoUserOperationQuote = {
    callGasLimit: Hex;
    fee: Hex;
    gas: Hex;
    l1Fee: Hex;
    preVerificationGas: Hex;
    verificationGasLimit: Hex;
};

export type RelayFeeQuote = {
    chainId: string;
    token: {
        address: Address;
        decimals: number;
    };
    fee: string;
    expiry: number;
    context: Hex;
};

export type GelatoBundlerRpcSchema = [
    {
        Method: 'gelato_getUserOperationQuote';
        Parameters: [userOperation: RpcUserOperation, entryPoint: Address, quoteToken: Address];
        ReturnType: GelatoUserOperationQuote;
    },
    {
        Method: 'eth_sendUserOperationSync';
        Parameters: [userOperation: RpcUserOperation, entryPoint: Address];
        ReturnType: RpcUserOperationReceipt;
    },
    {
        Method: 'eth_sendUserOperation';
        Parameters: [userOperation: RpcUserOperation, entryPoint: Address];
        ReturnType: Hex;
    },
    {
        Method: 'relayer_getFeeQuote';
        Parameters: { chainId: string; gas: string; token: Address };
        ReturnType: RelayFeeQuote;
    },
];

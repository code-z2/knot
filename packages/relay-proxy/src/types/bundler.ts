import type { Address, Client, Hex } from 'viem';
import type { RpcUserOperation, RpcUserOperationReceipt } from 'viem/account-abstraction';
import type { SupportedChainConfig } from './chain';

export type BundlerConfig = {
    chain: SupportedChainConfig;
    bundlerApiKey: string;
    jsonRpcApiKey: string;
};

export type SendUserOperationBatchResult =
    | {
          index: number;
          ok: true;
          hash: `0x${string}`;
      }
    | {
          index: number;
          ok: false;
          error: unknown;
      };

export type BundlerClient = Client & {
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
};

export type GelatoUserOperationQuote = {
    callGasLimit: Hex;
    fee: Hex;
    gas: Hex;
    l1Fee: Hex;
    preVerificationGas: Hex;
    verificationGasLimit: Hex;
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
];

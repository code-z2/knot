import type { Address, Client, Hex } from 'viem';
import type { RpcUserOperation, RpcUserOperationReceipt } from 'viem/account-abstraction';
import type { SupportedChainConfig } from './chain';

export type BundlerConfig = {
    chain: SupportedChainConfig;
    bundlerApiKey: string;
    jsonRpcApiKey: string;
};

export type CreateBundlerFactory<K extends Client> = (config: BundlerConfig) => K;

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

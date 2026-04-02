import type { Address, Hex } from 'viem';
import type { RpcUserOperation } from 'viem/account-abstraction';

export type IntentExecutionRecord = {
    attempts: number;
    chainId: number;
    createdAt: string;
    entryPoint: Address;
    expiresAt: string;
    fillId: Hex;
    lastAnomalyAt?: string;
    lastQueuedAt?: string;
    userOperation: RpcUserOperation;
};

export type IntentExecutionQueueMessage = Hex;

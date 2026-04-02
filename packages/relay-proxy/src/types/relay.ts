import type { Address, Hex } from 'viem';
import type { RpcUserOperation, RpcUserOperationReceipt } from 'viem/account-abstraction';
import type { GelatoUserOperationQuote, SendUserOperationBatchResult } from './bundler';

export type RelayPlanOperations = {
    background: readonly RpcUserOperation[];
    deferred: RpcUserOperation;
    immediate?: RpcUserOperation;
};

export type RelaySingleParams = {
    chainId: number;
    kind: 'single';
    request: readonly [operation: RpcUserOperation, entryPoint: Address];
};

export type RelayPlanParams = {
    chainId: number;
    fillId: Hex;
    kind: 'plan';
    request: readonly [operations: RelayPlanOperations, entryPoint: Address];
};

export type RelaySubmitParams = RelaySingleParams | RelayPlanParams;

export type RelaySingleQuoteContext = {
    kind: 'single';
    quote: GelatoUserOperationQuote;
};

export type RelayPlanQuoteContext = {
    backgroundQuotes: readonly GelatoUserOperationQuote[];
    immediateQuote?: GelatoUserOperationQuote;
    kind: 'plan';
};

export type RelayQuoteContext = RelaySingleQuoteContext | RelayPlanQuoteContext;

export type RelayDeferredResult = {
    fillId: Hex;
    queued: boolean;
};

export type RelaySingleResult = {
    kind: 'single';
    userOperationHash: Hex;
};

export type RelayPlanResult = {
    backgroundResults: readonly SendUserOperationBatchResult[];
    deferred: RelayDeferredResult;
    immediateReceipt?: RpcUserOperationReceipt;
    kind: 'plan';
};

export type RelaySubmitResult = RelayPlanResult | RelaySingleResult;

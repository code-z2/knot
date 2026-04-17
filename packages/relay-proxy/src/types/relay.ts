/**
 * Relay request/response type definitions.
 *
 * @module
 */
import type { Address, Hex } from 'viem';
import type { RpcUserOperation, RpcUserOperationReceipt } from 'viem/account-abstraction';
import type { GelatoUserOperationQuote, SendUserOperationBatchResult } from './bundler';
import { SupportedChainId } from './chain';

/**
 * Multi-phase relay plan — used for cross-chain intents.
 *
 * - `background`: Operations submitted in parallel (fire-and-forget).
 * - `deferred`: The intent-execution operation stored in KV for the
 *   queue worker to retry until the cross-chain fill confirms.
 * - `immediate`: synchronous operation that the handler waits
 *   for a receipt before returning or a singular userOperation without the cross-chain ceremony.
 */
export type RelayStrategy = 'immediate' | 'background' | 'deferred';

export type RelayOperation = {
    strategy: RelayStrategy;
    chainId: SupportedChainId;
} & RpcUserOperation;

export type RelayParams = {
    request: readonly [operations: RelayOperation[], entryPoint: Address];
};

export type RelayPlanParams = RelayParams & {
    fillId: Hex;
};

export type RelaySubmitParams = RelayParams | RelayPlanParams;

export type RelayQuoteContext = Record<number, GelatoUserOperationQuote>;

export type RelayDeferredResult = {
    fillId: Hex;
    queued: boolean;
};

export type RelayImmediateResult = {
    immediate: RpcUserOperationReceipt;
};

export type RelayPlanResult = {
    background: SendUserOperationBatchResult[];
    deferred: RelayDeferredResult;
};

export type RelaySubmitResult = Partial<RelayImmediateResult & RelayPlanResult>;

export type UnwrappedRelayOperation = {
    chainId: SupportedChainId;
    userOp: RpcUserOperation;
};

export type WrappedRelayOperation = RelayOperation & {
    unwrap: () => UnwrappedRelayOperation;
};

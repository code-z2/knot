import { createGasProfileStore } from '@/stores/gas';
import { uint } from '@/utils';
import type { Address, Call, Hex } from 'viem';
import { GasTankDORecord } from './durable-object';

export type GasProvider =
    | {
          gasTankAddress: Address;
          kind: 'knot';
      }
    | {
          kind: 'self';
      };

export type GasProfileRecord = {
    // the lower bound of how much -gative usdc a user can incure in gas spend.
    minimumAllowedUsdc: uint;
    // if the overdraft policy is applicable to the user
    overdraftEligible: boolean;
    // explicitly enabled by the user
    overdraftEnabled: boolean;
    // locked by the protocol: abuse, overdraft limit reached or withdrawal request with a -ve balance
    overdraftLocked: boolean;
    // the amount of usdc the user is in debt
    overdraftOutstandingUsdc: uint;
    // realized sponsored gas debt awaiting explicit collection
    outstandingDebtUsdc: uint;
    updatedAt: number;
    userId: string;
};

// --- STATUS ---

export type GasStatusParams = Record<string, never>;

export type GasStatusResult = {
    balanceUsdc: uint;
    minimumAllowedUsdc: uint;
    overdraftEligible: boolean;
    overdraftEnabled: boolean;
    overdraftLocked: boolean;
    overdraftOutstandingUsdc: uint;
    provider: GasProvider;
};

// --- HISTORY ---

export type GasWindow = '1y' | '3m' | '6m';

export type GasHistoryParams = {
    window?: GasWindow;
};

export type GasHistoryResult = {
    chains: Record<string, Hex>;
    totalUsdc: uint;
    updatedAt: string;
    window: GasWindow;
};

export type GasUsageBucketRecord = {
    chains: Record<string, uint>;
    totalUsdc: uint;
    updatedAt: string;
};

// --- OVERDRAFT ---

export type GasOverdraftUpdateParams = {
    action: 'disable' | 'enable';
};

export type GasOverdraftUpdateResult = {
    minimumAllowedUsdc: uint;
    overdraftEligible: boolean;
    overdraftEnabled: boolean;
    overdraftLocked: boolean;
    overdraftOutstandingUsdc: uint;
};

// --- WITHDRAW ---

export type GasWithdrawParams = {
    amount: uint;
    deadline: number;
    to: Address;
};

export type GasCollectionContext<T> = {
    balanceUsdc: uint;
    gasProfile: T;
    pendingExposureUsdc: uint;
    provider: GasProvider;
};

export type GasTankDebtMutationResult = {
    outstandingDebtUsdc: Hex;
};

export type GasClient = {
    encodeDebitCall: (userId: Address, amountUsdc: uint) => Promise<Call[]>;
    cosign: (userId: Address, params: GasWithdrawParams) => Promise<Hex>;
    getGasBalance: (userId: Address) => Promise<bigint>;
    getGasWithdrawalNonce: (userId: Address) => Promise<bigint>;
    getGasProvider: (userId: Address) => GasProvider;
    getGasTankAddress: (userId: Address) => Address;
    getRecord: (userId: Address) => Promise<GasTankDORecord>;
    admitExposure: (userId: Address, balance: uint, quote: uint) => Promise<GasTankDORecord>;
    decrementOutstandingDebt: (userId: Address, amountUsdc: uint) => Promise<GasTankDebtMutationResult>;
    decrementPendingExposure: (userId: Address, amountUsdc: uint) => Promise<GasTankDORecord>;
    incrementOutstandingDebt: (userId: Address, amountUsdc: uint) => Promise<GasTankDebtMutationResult>;
    incrementPendingExposure: (userId: Address, amountUsdc: uint) => Promise<GasTankDORecord>;
} & {
    ctx: <R = ReturnType<typeof createGasProfileStore> | undefined>(
        userId: Address,
        profileStore?: R,
    ) => Promise<GasCollectionContext<R extends undefined ? null : GasProfileRecord>>;
};

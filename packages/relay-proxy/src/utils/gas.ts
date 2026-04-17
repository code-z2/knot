/**
 * Gas-tank utility functions — pure helpers for GasTank contract
 * interactions, daily-usage bucket math, and Durable Object RPC.
 *
 * These utilities are stateless; they’re consumed by both the
 * {@link createGasClient} service and the gas route handlers.
 *
 * @module
 */
import {
    CREATE_X_ABI,
    CREATE_X_ADDRESS,
    GAS_TANK_ABI,
    GAS_TANK_CREATE_X_SALT,
    MAINNET_GAS_CHAIN,
    TESTNET_GAS_CHAIN,
} from '@/constants';
import type {
    ChainEnvironment,
    CloudflareBindings,
    GasProfileRecord,
    GasTankDOResponse,
    GasUsageBucketRecord,
    GasWindow,
    GasWithdrawParams,
} from '@/types';
import { type Address, Call, encodeDeployData, encodeFunctionData, getCreate2Address, type Hex, keccak256 } from 'viem';
import GasTankArtifact from '../../../../contracts/out/GasTank.sol/GasTank.json';
import { uint } from './uint';

export function getGasWindowDays(window: GasWindow) {
    switch (window) {
        case '6m':
            return 180;
        case '1y':
            return 365;
        case '3m':
        default:
            return 90;
    }
}

export function getGasChain(environment: ChainEnvironment) {
    if (environment === 'mainnet') {
        return MAINNET_GAS_CHAIN;
    }
    return TESTNET_GAS_CHAIN;
}

/**
 * Predict the CREATE2 address of a user’s GasTank contract.
 *
 * Uses the same salt and init code that `encodeGasTankContractDeployment`
 * produces, so the predicted address matches the actual deployment.
 * This is called **before** the contract is deployed so the gas service
 * can read the balance of a not-yet-deployed GasTank via `balanceOf`.
 */
export function predictGasTankAddress(owner: Address, cosigner: Address, environment: ChainEnvironment = 'mainnet') {
    const chain = getGasChain(environment);
    const initCode = encodeDeployData({
        abi: GAS_TANK_ABI,
        args: [owner, cosigner, chain.gelato.quoteToken],
        bytecode: GasTankArtifact.bytecode.object as Hex,
    });
    return getCreate2Address({
        bytecodeHash: keccak256(initCode),
        from: CREATE_X_ADDRESS,
        salt: GAS_TANK_CREATE_X_SALT,
    });
}

export function createDefaultGasProfile(userId: string): GasProfileRecord {
    return {
        minimumAllowedUsdc: uint.zero,
        overdraftEligible: false,
        overdraftEnabled: false,
        overdraftLocked: false,
        overdraftOutstandingUsdc: uint.zero,
        outstandingDebtUsdc: uint.zero,
        updatedAt: 0,
        userId,
    };
}

export function emptyUsageBucket(): GasUsageBucketRecord {
    return {
        chains: {},
        totalUsdc: uint.zero,
        updatedAt: new Date(0).toISOString(),
    };
}

/**
 * UTC date key for daily usage buckets.
 *
 * Returns `YYYY-MM-DD` for the given timestamp minus `offsetDays`.
 * Used to scan backwards when aggregating usage over a window.
 */
export function getUtcDateBucket(now = Date.now(), offsetDays = 0) {
    const date = new Date(now);
    date.setUTCDate(date.getUTCDate() - offsetDays);
    return date.toISOString().slice(0, 10);
}

export function incrementBucket(
    bucket: GasUsageBucketRecord,
    chainId: number,
    amountUsdc: uint,
    updatedAt: string,
): GasUsageBucketRecord {
    const chainKey = String(chainId);

    return {
        chains: {
            ...bucket.chains,
            [chainKey]: uint.add(bucket.chains[chainKey] ?? uint.zero, amountUsdc),
        },
        totalUsdc: uint.add(bucket.totalUsdc, amountUsdc),
        updatedAt,
    };
}

/**
 * Encode a CreateX `deployCreate2` call for the user’s GasTank.
 *
 * The deployment is idempotent via CREATE2 — calling this for a user
 * whose GasTank is already deployed will revert, so callers must
 * check `getCode` first (see `encodeDebitCall` in the gas service).
 */
export function encodeGasTankContractDeployment(owner: Address, cosigner: Address, usdc: Address): Call {
    const initCode = encodeDeployData({
        abi: GAS_TANK_ABI,
        args: [owner, cosigner, usdc],
        bytecode: GasTankArtifact.bytecode.object as Hex,
    });
    return {
        data: encodeFunctionData({
            abi: CREATE_X_ABI,
            functionName: 'deployCreate2',
            args: [GAS_TANK_CREATE_X_SALT, initCode],
        }),
        to: CREATE_X_ADDRESS,
        value: 0n,
    };
}

export function encodeGasTankDebit(amount: bigint, treasury: Address, gasTankAddress: Address): Call {
    return {
        data: encodeFunctionData({
            abi: GAS_TANK_ABI,
            functionName: 'debit',
            args: [amount, treasury],
        }),
        to: gasTankAddress,
        value: 0n,
    };
}

export function encodeGasTankWithdraw(gasTankAddress: Address, params: GasWithdrawParams, sig: Hex) {
    return {
        data: encodeFunctionData({
            abi: GAS_TANK_ABI,
            functionName: 'withdraw',
            args: [params.amount.value, params.to, BigInt(params.deadline), sig],
        }),
        to: gasTankAddress,
        value: 0n,
    };
}

/**
 * Build the EIP-712 typed data for a cosigned GasTank withdrawal.
 *
 * The GasTank contract’s `withdraw` function requires a signature over
 * this exact typed-data structure. The server signs it after verifying
 * the user has no outstanding debt, and the user submits both their own
 * signature and the server’s cosignature in the same transaction.
 */
export function getWithdrawTypedData(
    gasTankAddress: Address,
    chainId: number,
    params: GasWithdrawParams & { nonce: bigint },
) {
    return {
        domain: {
            name: 'KnotGasTank',
            version: '1',
            chainId: chainId,
            verifyingContract: gasTankAddress,
        },
        types: {
            withdraw: [
                { name: 'amount', type: 'uint256' },
                { name: 'to', type: 'address' },
                { name: 'nonce', type: 'uint256' },
                { name: 'deadline', type: 'uint256' },
            ],
        },
        primaryType: 'withdraw' as const,
        message: {
            amount: params.amount.value,
            to: params.to,
            nonce: params.nonce,
            deadline: BigInt(params.deadline),
        },
    };
}

/**
 * Build a Durable Object RPC caller for the `GAS_TANK_DO` binding.
 *
 * Returns a typed function that routes requests to the DO instance
 * keyed by `userId`. The DO uses a synthetic URL (`https://gas-tank/...`)
 * because Durable Objects require a `Request` but don’t actually serve
 * real HTTP — the URL is only used for internal routing.
 */
export function gasTankDORequestHandler(env: Pick<CloudflareBindings, 'GAS_TANK_DO'>) {
    return async <Result>(userId: string, path: string, init?: RequestInit) => {
        const id = env.GAS_TANK_DO.idFromName(userId);
        const stub = env.GAS_TANK_DO.get(id);
        const response = await stub.fetch(new Request(`https://gas-tank${path}?userId=${userId}`, init));
        const json = await response.json<GasTankDOResponse<Result>>();

        if (!json.ok) {
            throw new Error(json.reason);
        }

        return json.result;
    };
}

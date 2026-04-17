import type { Address } from 'viem';
import { arbitrum, arbitrumSepolia, base, baseSepolia, sepolia } from 'viem/chains';

import type { ChainRegistry } from '@/types';
import { entryPoint07Address, entryPoint08Address, entryPoint09Address } from 'viem/account-abstraction';
import z from 'zod';
import { USDC_BY_CHAIN } from './addresses';

export const MAINNET_CHAIN_IDS = [8453, 42161] as const;
export const MAINNET_CHAIN_IDZ = z.union(MAINNET_CHAIN_IDS.map((id) => z.literal(id)));

export const TESTNET_CHAIN_IDS = [84532, 421614, 11155111] as const;
export const TESTNET_CHAIN_IDZ = z.union(TESTNET_CHAIN_IDS.map((id) => z.literal(id)));

export const SUPPORTED_ENTRY_POINTS = [
    entryPoint07Address,
    entryPoint08Address,
    entryPoint09Address,
] as const satisfies readonly Address[];

export const FAUCET_NATIVE_AMOUNT = '0.01';
export const FAUCET_USDC_AMOUNT = '2';

export const MAINNET_CHAINS = [
    {
        ...base,
        enabled: true,
        environment: 'mainnet',
        gelato: {
            quoteToken: USDC_BY_CHAIN[8453],
        },
        supportedEntryPoints: SUPPORTED_ENTRY_POINTS,
    },
    {
        ...arbitrum,
        enabled: true,
        environment: 'mainnet',
        gelato: {
            quoteToken: USDC_BY_CHAIN[42161],
        },
        supportedEntryPoints: SUPPORTED_ENTRY_POINTS,
    },
] as const;

export const TESTNET_CHAINS = [
    {
        ...baseSepolia,
        enabled: true,
        environment: 'testnet',
        faucet: {
            assets: [
                {
                    amount: FAUCET_NATIVE_AMOUNT,
                    kind: 'native',
                },
                {
                    amount: FAUCET_USDC_AMOUNT,
                    kind: 'erc20',
                    token: USDC_BY_CHAIN[84532],
                },
            ],
        },
        gelato: {
            quoteToken: USDC_BY_CHAIN[84532],
        },
        supportedEntryPoints: SUPPORTED_ENTRY_POINTS,
    },
    {
        ...arbitrumSepolia,
        enabled: true,
        environment: 'testnet',
        faucet: {
            assets: [
                {
                    amount: FAUCET_NATIVE_AMOUNT,
                    kind: 'native',
                },
                {
                    amount: FAUCET_USDC_AMOUNT,
                    kind: 'erc20',
                    token: USDC_BY_CHAIN[421614],
                },
            ],
        },
        gelato: {
            quoteToken: USDC_BY_CHAIN[421614],
        },
        supportedEntryPoints: SUPPORTED_ENTRY_POINTS,
    },
    {
        ...sepolia,
        enabled: true,
        environment: 'testnet',
        faucet: {
            assets: [
                {
                    amount: FAUCET_NATIVE_AMOUNT,
                    kind: 'native',
                },
                {
                    amount: FAUCET_USDC_AMOUNT,
                    kind: 'erc20',
                    token: USDC_BY_CHAIN[11155111],
                },
            ],
        },
        gelato: {
            quoteToken: USDC_BY_CHAIN[11155111],
        },
        supportedEntryPoints: SUPPORTED_ENTRY_POINTS,
    },
] as const;

export const CHAIN_REGISTRY = {
    8453: MAINNET_CHAINS[0],
    42161: MAINNET_CHAINS[1],
    84532: TESTNET_CHAINS[0],
    421614: TESTNET_CHAINS[1],
    11155111: TESTNET_CHAINS[2],
} as const satisfies ChainRegistry;

export const MAINNET_GAS_CHAIN = CHAIN_REGISTRY[8453];
export const TESTNET_GAS_CHAIN = CHAIN_REGISTRY[84532];

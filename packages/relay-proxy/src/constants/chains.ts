import type { Address } from 'viem';
import { arbitrum, arbitrumSepolia, base, baseSepolia, sepolia } from 'viem/chains';

import type { ChainRegistry, MainnetChainId, TestnetChainId } from '@/types';
import { USDC_BY_CHAIN } from '@/constants/usdc';

export const MAINNET_CHAIN_IDS = [8453, 42161] as const satisfies readonly MainnetChainId[];

export const TESTNET_CHAIN_IDS = [
    84532, 421614, 11155111,
] as const satisfies readonly TestnetChainId[];

export const ENTRY_POINT_V07 =
    '0x0000000071727De22E5E9d8BAf0edAc6f37da032' as const satisfies Address;
export const ENTRY_POINT_V08 =
    '0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108' as const satisfies Address;
export const ENTRY_POINT_V09 =
    '0x433709009B8330FDa32311DF1C2AFA402eD8D009' as const satisfies Address;

export const SUPPORTED_ENTRY_POINTS = [
    ENTRY_POINT_V07,
    ENTRY_POINT_V08,
    ENTRY_POINT_V09,
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

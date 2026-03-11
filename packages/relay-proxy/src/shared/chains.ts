/**
 * Centralized chain resolution and RPC transport.
 *
 * Alchemy-enhanced chain definitions (from @account-kit/infra) are preferred
 * because they embed the Alchemy RPC base URL in `rpcUrls.alchemy.http[0]`.
 * And by default, (we use alchemy rpcs, so whatever chains alchemy surpports, we support)
 * Plain viem chains may serve as fallback for any chain Alchemy doesn't support.
 */
import { createPublicClient, extractChain, http, type Chain, type PublicClient } from 'viem';
import * as infraChains from '@account-kit/infra';
import { alchemy } from '@account-kit/infra';

import { BadRequestError } from './errors';

// ---------------------------------------------------------------------------
// Chain resolution
// ---------------------------------------------------------------------------

/** Every chain alchemy knows about, filtered to valid Chain objects. */
export const ALL_KNOWN_CHAINS: readonly Chain[] = Object.values(infraChains).filter(
    (v): v is Chain => !!v && typeof v === 'object' && 'id' in v && 'rpcUrls' in v,
);

/** Testnet chains used by the faucet. */
export const FAUCET_CHAINS: readonly Chain[] = [
    infraChains.sepolia,
    infraChains.baseSepolia,
    infraChains.arbitrumSepolia,
];

/**
 * Resolves a numeric chain ID to a viem Chain definition.
 * Prefers the Alchemy-enhanced definition when available.
 * @throws BadRequestError if the chain ID is not recognized.
 */
export function extractKnownChain(chainId: number): Chain {
    const chain = extractChain({
        chains: ALL_KNOWN_CHAINS as Chain[],
        id: chainId,
    });
    if (!chain) {
        throw new BadRequestError(`Unsupported chain ${chainId}.`);
    }
    return chain;
}

// ---------------------------------------------------------------------------
// RPC client factory
// ---------------------------------------------------------------------------

/**
 * Creates a viem PublicClient using an Alchemy RPC when the chain supports it.
 * Falls back to the chain's default public RPC if no Alchemy URL or API key.
 */
export function createChainClient(chainId: number, alchemyApiKey?: string): PublicClient {
    const chain = extractKnownChain(chainId);
    return createPublicClient({
        chain,
        transport: alchemyApiKey ? alchemy({ apiKey: alchemyApiKey }) : http(),
    });
}

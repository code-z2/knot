/**
 * Chain-registry utilities — type-safe lookups, relay-operation
 * destructuring, and chain-set queries.
 *
 * These functions bridge the gap between raw numeric chain IDs (which
 * arrive as JSON-RPC params) and the fully-typed {@link SupportedChainConfig}
 * objects needed by the bundler and gas services.
 *
 * @module
 */
import { CHAIN_REGISTRY, MAINNET_CHAIN_IDS, TESTNET_CHAIN_IDS } from '@/constants';
import type {
    ChainEnvironment,
    MainnetChainConfig,
    MainnetChainId,
    PublicChainDescriptor,
    SupportedChainConfig,
    SupportedChainId,
    TestnetChainConfig,
    TestnetChainId,
} from '@/types';
import { Address, isAddress } from 'viem';

/** Type guard: narrows a runtime `number` to the `SupportedChainId` union. */
export function isSupportedChainId(chainId: number): chainId is SupportedChainId {
    return chainId in CHAIN_REGISTRY;
}

export function isMainnetChainId(chainId: number): chainId is MainnetChainId {
    return (MAINNET_CHAIN_IDS as readonly number[]).includes(chainId);
}

export function isTestnetChainId(chainId: number): chainId is TestnetChainId {
    return (TESTNET_CHAIN_IDS as readonly number[]).includes(chainId);
}

export function getChainConfig(chainId: SupportedChainId): SupportedChainConfig {
    return CHAIN_REGISTRY[chainId];
}

/** Returns the list of all supported mainnet chain configurations. */
export function getMainnetChains(): readonly MainnetChainConfig[] {
    return MAINNET_CHAIN_IDS.map((chainId) => CHAIN_REGISTRY[chainId]);
}

/** Returns the list of all supported testnet chain configurations. */
export function getTestnetChains(): readonly TestnetChainConfig[] {
    return TESTNET_CHAIN_IDS.map((chainId) => CHAIN_REGISTRY[chainId]);
}

/** Returns the list of supported chain configurations, optionally filtered by environment. */
export function getSupportedChains(environment?: ChainEnvironment): readonly SupportedChainConfig[] {
    if (environment === 'mainnet') {
        return getMainnetChains();
    }

    if (environment === 'testnet') {
        return getTestnetChains();
    }

    return [...getMainnetChains(), ...getTestnetChains()];
}

export function buildJsonRpcUrl(chainId: SupportedChainId, apiKey: string) {
    return `https://edge.goldsky.com/standard/evm/${chainId}?secret=${apiKey}`;
}

export function buildBundlerUrl(chainId: number) {
    return `https://api.gelato.cloud/rpc/${chainId}?payment=sponsored`;
}

/**
 * Verify that **all** chains in a relay request share the given entry point.
 *
 * A cross-chain plan must use a
 * consistent entry point across all participating chains. A single chain
 * not supporting the entry point would cause the UserOp to revert.
 */
export function isSupportedEntryPoints(chainConfigs: readonly SupportedChainConfig[], entryPoint: Address) {
    return chainConfigs.every((config) => config.supportedEntryPoints.includes(entryPoint));
}

/**
 * Pull the entry point address from a raw relay request tuple.
 *
 * The request is `[operation(s), entryPoint?]` — the entry point is at
 * index 1 and is optional. Returns `null` if missing or not a valid
 * address, letting callers skip the entry-point check entirely.
 */
export function getEntryPointFromRequest(request: readonly [unknown, string]) {
    const entryPoint = request[1];
    return entryPoint && isAddress(entryPoint) ? entryPoint : null;
}

export function toPublicChainDescriptor(chain: SupportedChainConfig): PublicChainDescriptor {
    return {
        chainId: chain.id,
        environment: chain.environment,
        name: chain.name,
    };
}

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

export function isSupportedChainId(chainId: number): chainId is SupportedChainId {
    return chainId in CHAIN_REGISTRY;
}

export function isMainnetChainId(chainId: number): chainId is MainnetChainId {
    return (MAINNET_CHAIN_IDS as readonly number[]).includes(chainId);
}

export function isTestnetChainId(chainId: number): chainId is TestnetChainId {
    return (TESTNET_CHAIN_IDS as readonly number[]).includes(chainId);
}

export function getChainConfig(chainId: number | null | undefined): SupportedChainConfig | null {
    if (chainId === null || chainId === undefined) {
        return null;
    }
    if (!isSupportedChainId(chainId)) {
        return null;
    }

    return CHAIN_REGISTRY[chainId];
}

export function getMainnetChains(): readonly MainnetChainConfig[] {
    return MAINNET_CHAIN_IDS.map((chainId) => CHAIN_REGISTRY[chainId]);
}

export function getTestnetChains(): readonly TestnetChainConfig[] {
    return TESTNET_CHAIN_IDS.map((chainId) => CHAIN_REGISTRY[chainId]);
}

export function getSupportedChains(
    environment?: ChainEnvironment,
): readonly SupportedChainConfig[] {
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

export function isSupportedEntryPoint(chain: SupportedChainConfig, entryPoint: string) {
    return chain.supportedEntryPoints.includes(entryPoint as `0x${string}`);
}

export function getEntryPointFromRequest(request?: readonly [unknown, string?]) {
    const entryPoint = request?.[1];
    return typeof entryPoint === 'string' ? entryPoint : null;
}

export function toPublicChainDescriptor(chain: SupportedChainConfig): PublicChainDescriptor {
    return {
        chainId: chain.id,
        environment: chain.environment,
        name: chain.name,
    };
}

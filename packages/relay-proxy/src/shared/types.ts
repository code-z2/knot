/**
 * Shared types used across all modules (relay, upload, faucet, singleton).
 * Domain-specific types live in their respective modules.
 */
import type { Address } from 'viem';

/** Cloudflare Worker environment bindings. */
export interface Env {
    // KV Namespaces
    GAS_TANK_KV: KVNamespace;
    DEFERRED_RELAY_KV: KVNamespace;
    FAUCET_FUNDING_KV?: KVNamespace;

    // Queues
    RELAY_BATCH_QUEUE: Queue;
    ALERTS_QUEUE: Queue;

    // Durable Objects
    FAUCET_TRACKER_DO?: DurableObjectNamespace;
    WEBHOOK_TRACKER: DurableObjectNamespace;

    // Auth
    RELAY_AUTH_TOKEN: string;
    RELAY_AUTH_HMAC_SECRET?: string;

    // Gelato
    GELATO_MAINNET_API_KEY?: string;
    GELATO_TESTNET_API_KEY?: string;
    GELATO_SYNC_TIMEOUT_MS?: string;

    // Pinata
    PINATA_JWT: string;
    PINATA_GATEWAY_BASE_URL: string;
    PINATA_GROUP_CONFIG: Record<string, string>;
    PINATA_SIGN_EXPIRES_SECONDS?: string;
    PINATA_MAX_FILE_SIZE_BYTES?: string;

    // Alchemy
    ALCHEMY_NODE_API_KEY?: string;
    ALCHEMY_WEBHOOK_API_KEY?: string;
    ALCHEMY_WEBHOOK_SIGNING_KEYS?: string;

    // Alerts
    DISCORD_ANOMALY_WEBHOOK_URL?: string;

    // Secrets
    SERVER_KEY_STORE?: SecretsStoreSecret;

    // Config
    SINGLETON_CONFIG?: SingletonConfig;

    // Credit & Accounting
    INITIAL_CREDIT_NATIVE?: string;
    FLOOR_LIMITED_TESTNET_NATIVE?: string;
    FLOOR_LIMITED_MAINNET_NATIVE?: string;
    FLOOR_FULL_MAINNET_NATIVE?: string;
}

export type SupportMode = 'LIMITED_TESTNET' | 'LIMITED_MAINNET' | 'FULL_MAINNET';

export interface SingletonModeConfig {
    address: string;
    accumulatorFactory: string;
    version: string;
    releaseNotes?: string;
}

export type SingletonConfig = Partial<Record<SupportMode, SingletonModeConfig>>;

export interface DirectUploadRequestModel {
    eoaAddress: string;
    fileName: string;
    contentType: string;
    supportMode: string;
}

export interface NormalizedDirectUploadRequestModel {
    eoaAddress: string;
    fileName: string;
    contentType: string;
    supportMode: SupportMode;
    imageID: string;
}

export interface FaucetFundRequestModel {
    eoaAddress: string;
    supportMode: SupportMode;
}

export interface PaymentOptionModel {
    chainId: number;
    tokenAddress: Address;
    symbol: string;
    amount: string;
}

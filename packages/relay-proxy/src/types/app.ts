import type { Address, Hex } from 'viem';
import type { AnomalyQueueMessage } from './anomaly';
import type { AppAttestVerifier, AuthConfig, AuthStore, PasskeyVerifier, SessionRecord } from './auth';
import type { BundlerClient } from './bundler';
import type { ChainPolicyContext } from './chain';
import type { GasClient } from './gas';
import type { IntentExecutionQueueMessage } from './intent-execution';
import type { RelayQuoteContext } from './relay';
import type { UploadClient } from './upload';

/**
 * Worker bindings required by the active auth surface.
 */
export type CloudflareBindings = {
    AUTH_DB: D1Database;
    AUTH_KV: KVNamespace;

    FAUCET_DO: DurableObjectNamespace;

    GAS_TANK_DO: DurableObjectNamespace;
    GAS_TANK_DB: D1Database;
    GAS_USAGE_KV: KVNamespace;
    TREASURY_ADDRESS: Hex;

    RELAY_KV: KVNamespace;
    RELAY_QUEUE: Queue<IntentExecutionQueueMessage>;

    ANOMALY_QUEUE: Queue<AnomalyQueueMessage>;
    DISCORD_WEBHOOK_URL?: string;

    BUNDLER_API_KEY: SecretsStoreSecret;
    JSON_RPC_API_KEY: SecretsStoreSecret;
    SERVER_KEY: SecretsStoreSecret;

    KNOT_APPLE_BUNDLE_ID: string;
    KNOT_APPLE_TEAM_ID: string;
    KNOT_APP_ATTEST_ALLOW_DEVELOPMENT: string;

    KNOT_RP_ID: string;
    KNOT_RP_NAME: string;
    KNOT_RP_ORIGIN: string;

    PINATA_GATEWAY_BASE_URL: string;
    PINATA_IMAGE_GROUP_ID: string;
    PINATA_JWT: string;
    PINATA_MAX_FILE_SIZE_BYTES?: string;
    PINATA_SIGN_EXPIRES_SECONDS?: string;

    ACCOUNT_IMPLEMENTATION: Address;
    CROSS_CHAIN_EXECUTOR_MODULE: Address;
    ACCUMULATOR_MODULE: Address;
    MERKLE_VALIDATOR_MODULE: Address;
    SPOKE_POOL: Address;
    CONSUMER_HUB: Address;
    GX: Hex;
    GY: Hex;
};

/**
 * Dependency injection surface used by tests to replace the production auth
 * runtime with in-memory fixtures.
 */
export type CreateAppOptions = {
    auth?: {
        config: AuthConfig;
        store: AuthStore;
        verifiers: {
            appAttest: AppAttestVerifier;
            passkey: PasskeyVerifier;
        };
    };
    gasClient?: GasClient;
    bundler?: BundlerClient;
    upload?: UploadClient;
};

/**
 * Hono bindings and request-scoped variables used by relay-proxy.
 *
 * `Variables` only contains `session` — set by the {@link auth} middleware
 * after the bearer token is validated. Request body validation is handled
 * entirely by `zValidator` (see `schemas/rpc.ts`), so there is no `rpc` or
 * `rawBody` variable. Handlers access the validated body via
 * `c.req.valid('json')` which is fully typed by the route's zod schema.
 */
export type AppBindings = {
    Bindings: CloudflareBindings;
    Variables: {
        chain: ChainPolicyContext;
        quotes: RelayQuoteContext;
        session: SessionRecord;
    };
};

export type AppBatchQueue =
    | (MessageBatch<AnomalyQueueMessage> & {
          readonly queue: 'anomaly-queue';
      })
    | (MessageBatch<IntentExecutionQueueMessage> & {
          readonly queue: 'intent-execution-queue';
      });

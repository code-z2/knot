import type {
    AppAttestVerifier,
    AuthConfig,
    AuthStore,
    PasskeyVerifier,
    SessionRecord,
} from './auth';
import type { RelayQuoteContext } from './relay';
import type { SupportedChainConfig } from './chain';
import type { UploadRuntime } from './upload';

/**
 * Worker bindings required by the active auth surface.
 */
export type CloudflareBindings = {
    AUTH_DB: D1Database;
    AUTH_KV: KVNamespace;

    BUNDLER_API_KEY?: string;
    JSON_RPC_API_KEY?: string;

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
    upload?: UploadRuntime;
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
        chain: SupportedChainConfig;
        relayQuote: RelayQuoteContext;
        session: SessionRecord;
    };
};

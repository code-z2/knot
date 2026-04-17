import { createAuthStore } from '@/stores/auth';
import type { AppBindings, AuthConfig, CloudflareBindings, CreateAppOptions } from '@/types';
import { createAppAttestVerifier, createPasskeyVerifier } from './verifiers';

/**
 * Reads auth configuration from Cloudflare runtime bindings.
 */
function createAuthConfig(env: CloudflareBindings): AuthConfig {
    return {
        appAttestAllowDevelopment: env.KNOT_APP_ATTEST_ALLOW_DEVELOPMENT == 'true',
        appBundleId: env.KNOT_APPLE_BUNDLE_ID,
        appTeamId: env.KNOT_APPLE_TEAM_ID,
        rpId: env.KNOT_RP_ID,
        rpName: env.KNOT_RP_NAME,
        rpOrigin: env.KNOT_RP_ORIGIN,
    };
}

/**
 * Builds the production auth runtime from Worker bindings.
 */
function createAuth(env: AppBindings['Bindings'], config: AuthConfig) {
    return {
        config,
        store: createAuthStore(env),
        verifiers: {
            appAttest: createAppAttestVerifier(config),
            passkey: createPasskeyVerifier(config),
        },
    };
}

/**
 * Returns the injected auth runtime when tests provide one, otherwise creates
 * the Cloudflare-backed runtime.
 */
export function createAuthClient(env: AppBindings['Bindings'], options: Pick<CreateAppOptions, 'auth'>) {
    return options.auth ?? createAuth(env, createAuthConfig(env));
}

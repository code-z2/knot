import { CHALLENGE_TTL_SECONDS, NONCE_TTL_SECONDS } from '@/constants';
import type {
    AppAttestationRecord,
    AuthStore,
    ChallengeRecord,
    CloudflareBindings,
    PasskeyRecord,
    SessionRecord,
    UserRecord,
} from '@/types';
import { createKVChallengeKey, createKVNonceKey, parseJsonRecord } from '@/utils';

/**
 * Creates the Cloudflare-backed auth store.
 *
 * Durable identity and session records live in D1. One-time challenges and
 * replay nonces live in KV with short TTLs.
 */
export function createAuthStore(env: Pick<CloudflareBindings, 'AUTH_DB' | 'AUTH_KV'>): AuthStore {
    return {
        async storeChallenge(challenge, ttlSeconds = CHALLENGE_TTL_SECONDS) {
            await env.AUTH_KV.put(createKVChallengeKey(challenge.id), JSON.stringify(challenge), {
                expirationTtl: ttlSeconds,
            });

            return challenge;
        },

        async consumeChallenge(id, kind) {
            const key = createKVChallengeKey(id);
            const record = parseJsonRecord<ChallengeRecord>(await env.AUTH_KV.get(key));

            if (!record || record.kind !== kind) {
                return null;
            }

            await env.AUTH_KV.delete(key);
            return record;
        },

        async consumeNonce(appAttestKeyId, nonce, ttlSeconds = NONCE_TTL_SECONDS) {
            const key = createKVNonceKey(appAttestKeyId, nonce);
            const existing = await env.AUTH_KV.get(key);

            if (existing) {
                return false;
            }

            await env.AUTH_KV.put(key, '1', {
                expirationTtl: ttlSeconds,
            });

            return true;
        },

        async createSession(session) {
            await env.AUTH_DB.prepare(
                `insert into sessions (id, access_token, refresh_token, app_attest_key_id, user_id, issued_at, expires_at, status)
           values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`,
            )
                .bind(
                    session.id,
                    session.accessToken,
                    session.refreshToken,
                    session.appAttestKeyId,
                    session.userId,
                    session.issuedAt,
                    session.expiresAt,
                    session.status,
                )
                .run();

            return session;
        },

        async getSession(accessToken) {
            const result = await env.AUTH_DB.prepare(
                `select id, access_token as accessToken, refresh_token as refreshToken, app_attest_key_id as appAttestKeyId, user_id as userId, issued_at as issuedAt, expires_at as expiresAt, status
           from sessions
           where access_token = ?1`,
            )
                .bind(accessToken)
                .first<SessionRecord | null>();

            return result ?? null;
        },

        async revokeSession(accessToken) {
            const session = await this.getSession(accessToken);

            if (!session) {
                return { ok: false };
            }

            await env.AUTH_DB.prepare(
                `update sessions
           set status = 'revoked'
           where access_token = ?1`,
            )
                .bind(accessToken)
                .run();

            return {
                ok: true,
            };
        },

        async createUser(user) {
            await env.AUTH_DB.prepare(
                `insert into users (id, created_at, status)
           values (?1, ?2, ?3)`,
            )
                .bind(user.id, user.createdAt, user.status)
                .run();

            return user;
        },

        async getUser(id) {
            const result = await env.AUTH_DB.prepare(
                `select id, created_at as createdAt, status
           from users
           where id = ?1`,
            )
                .bind(id)
                .first<UserRecord | null>();

            return result ?? null;
        },

        async createPasskey(passkey) {
            await env.AUTH_DB.prepare(
                `insert into passkeys (credential_id, user_id, public_key, counter, created_at)
           values (?1, ?2, ?3, ?4, ?5)`,
            )
                .bind(passkey.credentialId, passkey.userId, passkey.publicKey, passkey.counter, passkey.createdAt)
                .run();

            return passkey;
        },

        async getPasskey(credentialId) {
            const result = await env.AUTH_DB.prepare(
                `select credential_id as credentialId, user_id as userId, public_key as publicKey, counter, created_at as createdAt
           from passkeys
           where credential_id = ?1`,
            )
                .bind(credentialId)
                .first<PasskeyRecord | null>();

            return result ?? null;
        },

        async createAttestation(attestation) {
            await env.AUTH_DB.prepare(
                `insert into app_attestations (key_id, public_key, sign_count, environment, created_at, updated_at, status)
           values (?1, ?2, ?3, ?4, ?5, ?6, ?7)
           on conflict(key_id) do update set
             public_key = excluded.public_key,
             sign_count = excluded.sign_count,
             environment = excluded.environment,
             updated_at = excluded.updated_at,
             status = excluded.status`,
            )
                .bind(
                    attestation.keyId,
                    attestation.publicKey,
                    attestation.signCount,
                    attestation.environment,
                    attestation.createdAt,
                    attestation.updatedAt,
                    attestation.status,
                )
                .run();

            return attestation;
        },

        async getAttestation(index) {
            const result = await env.AUTH_DB.prepare(
                `select key_id as keyId, public_key as publicKey, sign_count as signCount, environment, created_at as createdAt, updated_at as updatedAt, status
           from app_attestations
           where ${index.id} = ?1`,
            )
                .bind(index.value)
                .first<AppAttestationRecord | null>();

            return result ?? null;
        },

        async updateAttestation(keyId, signCount, updatedAt) {
            await env.AUTH_DB.prepare(
                `update app_attestations
           set sign_count = ?2, updated_at = ?3
           where key_id = ?1`,
            )
                .bind(keyId, signCount, updatedAt)
                .run();
        },
    };
}

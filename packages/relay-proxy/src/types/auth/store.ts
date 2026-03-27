import type {
    AppAttestationRecord,
    ChallengeKind,
    ChallengeRecord,
    PasskeyRecord,
    SessionRecord,
    UserRecord,
} from './records';

/**
 * Storage contract for relay-proxy auth state.
 *
 * Services depend on this interface so the runtime can swap Cloudflare-backed
 * storage for test fixtures without changing route logic.
 */
export type AuthStore = {
    storeChallenge: (challenge: ChallengeRecord, ttlSeconds: number) => Promise<ChallengeRecord>;
    consumeChallenge: (id: string, kind: ChallengeKind) => Promise<ChallengeRecord | null>;

    consumeNonce: (appAttestKeyId: string, nonce: string, ttlSeconds: number) => Promise<boolean>;

    createSession: (session: SessionRecord) => Promise<SessionRecord>;
    getSession: (accessToken: string) => Promise<SessionRecord | null>;
    revokeSession: (accessToken: string) => Promise<{ ok: boolean }>;

    createUser: (user: UserRecord) => Promise<UserRecord | null>;
    getUser: (id: string) => Promise<UserRecord | null>;

    createPasskey: (passkey: PasskeyRecord) => Promise<PasskeyRecord | null>;
    getPasskey: (credentialId: string) => Promise<PasskeyRecord | null>;

    createAttestation: (attestation: AppAttestationRecord) => Promise<AppAttestationRecord>;
    getAttestation: (
        index: { id: 'key_id'; value: string } | { id: 'public_key'; value: string },
    ) => Promise<AppAttestationRecord | null>;
    updateAttestation: (keyId: string, signCount: number, updatedAt: number) => Promise<void>;
};

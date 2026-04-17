import { Address } from 'viem';

export type ChallengeKind = 'user_register' | 'user_login';

/**
 * One-time challenge record shared by passkey and App Attest verification for
 * a single register or login flow.
 */
export type ChallengeRecord = {
    challenge: string;
    /** Bound only for login flows. */
    credentialId: string | null;
    createdAt: number;
    id: string;
    kind: ChallengeKind;
    userId: Address;
};

/**
 * Server-side App Attest state for one attested app installation.
 */
export type AppAttestationRecord = {
    createdAt: number;
    environment: 'development' | 'production';
    keyId: string;
    publicKey: string;
    /** Last accepted App Attest sign count. */
    signCount: number;
    status: 'active' | 'revoked';
    updatedAt: number;
};

/**
 * Product-level user identity. Authentication credentials are stored
 * separately so credential rotation does not redefine the user object.
 */
export type UserRecord = {
    createdAt: number;
    id: Address;
    status: 'active' | 'revoked';
};

/**
 * Stored passkey credential bound to a user.
 */
export type PasskeyRecord = {
    /** Last counter returned during credential registration. */
    counter: number;
    createdAt: number;
    credentialId: string;
    publicKey: string;
    userId: Address;
};

/**
 * Bearer session issued after successful register/login verification.
 */
export type SessionRecord = {
    accessToken: string;
    /** Attested app key that is allowed to use this session on high-fidelity routes. */
    appAttestKeyId: string;
    expiresAt: number;
    id: string;
    issuedAt: number;
    refreshToken: string;
    status: 'active' | 'expired' | 'revoked';
    userId: Address;
};

import type {
    AppAttestVerifier,
    AppAttestationRecord,
    AuthConfig,
    AuthStore,
    CreateAppOptions,
    PasskeyRecord,
    PasskeyVerifier,
    SessionRecord,
    UserRecord,
} from '../../src/types';
import { createKVNonceKey } from '../../src/utils';

type AuthenticationOptions = ReturnType<PasskeyVerifier['getAuthenticationOptions']>;
type RegistrationOptions = ReturnType<PasskeyVerifier['getRegistrationOptions']>;
type RegistrationVerification = ReturnType<PasskeyVerifier['verifyRegistration']>;
const testPasskeyPublicKey = `0x${'11'.repeat(33)}` as const;

export function createMemoryAuthStore(): AuthStore {
    const attestations = new Map<string, AppAttestationRecord>();
    const challenges = new Map<string, import('../../src/types').ChallengeRecord>();
    const nonces = new Map<string, number>();
    const passkeys = new Map<string, PasskeyRecord>();
    const sessions = new Map<string, SessionRecord>();
    const users = new Map<string, UserRecord>();

    return {
        async storeChallenge(challenge) {
            challenges.set(challenge.id, challenge);
            return challenge;
        },

        async consumeChallenge(id, kind) {
            const challenge = challenges.get(id);

            if (!challenge || challenge.kind !== kind) {
                return null;
            }

            challenges.delete(id);
            return challenge;
        },

        async consumeNonce(appAttestKeyId, nonce) {
            const key = createKVNonceKey(appAttestKeyId, nonce);

            if (nonces.has(key)) {
                return false;
            }

            nonces.set(key, Date.now());
            return true;
        },

        async createSession(session) {
            sessions.set(session.accessToken, session);
            return session;
        },

        async getSession(accessToken) {
            return sessions.get(accessToken) ?? null;
        },

        async revokeSession(accessToken) {
            const session = sessions.get(accessToken);

            if (!session) {
                return { ok: false };
            }

            sessions.set(accessToken, {
                ...session,
                status: 'revoked',
            });

            return { ok: true };
        },

        async createUser(user) {
            if (users.has(user.id)) {
                return null;
            }

            users.set(user.id, user);
            return user;
        },

        async getUser(id) {
            return users.get(id) ?? null;
        },

        async createPasskey(passkey) {
            if (passkeys.has(passkey.credentialId)) {
                return null;
            }

            passkeys.set(passkey.credentialId, passkey);
            return passkey;
        },

        async getPasskey(credentialId) {
            return passkeys.get(credentialId) ?? null;
        },

        async createAttestation(attestation) {
            attestations.set(attestation.keyId, attestation);
            return attestation;
        },

        async getAttestation(index) {
            if (index.id === 'key_id') {
                return attestations.get(index.value) ?? null;
            }

            for (const attestation of attestations.values()) {
                if (attestation.publicKey === index.value) {
                    return attestation;
                }
            }

            return null;
        },

        async updateAttestation(keyId, signCount, updatedAt) {
            const attestation = attestations.get(keyId);

            if (!attestation) {
                return;
            }

            attestations.set(keyId, {
                ...attestation,
                signCount,
                updatedAt,
            });
        },
    };
}

const testConfig: AuthConfig = {
    appAttestAllowDevelopment: true,
    appBundleId: 'app.knot.ios',
    appTeamId: 'TEAM123456',
    rpId: 'knot.fi',
    rpName: 'Knot',
    rpOrigin: 'https://knot.fi',
};

const testPasskeyVerifier: PasskeyVerifier = {
    getAuthenticationOptions(credentialId, challenge) {
        const options = {
            challenge,
        };

        return options as unknown as AuthenticationOptions;
    },

    getRegistrationOptions(userId, challenge) {
        const options = {
            challenge,
            userId,
        };

        return options as unknown as RegistrationOptions;
    },

    verifyAuthentication(input) {
        return input.response.id === 'credential-login';
    },

    verifyRegistration(input) {
        const result = {
            counter: 0,
            credential: {
                id: input.credential.id,
                publicKey: testPasskeyPublicKey,
            },
        };

        return result as unknown as RegistrationVerification;
    },
};

const testAppAttestVerifier: AppAttestVerifier = {
    verifyAssertion(input) {
        if (!input.assertion.startsWith('assertion:')) {
            throw new Error('invalid assertion');
        }

        return {
            signCount: input.signCount + 1,
        };
    },

    verifyAttestation(input) {
        if (!input.attestation.startsWith('attestation:')) {
            throw new Error('invalid attestation');
        }

        return {
            environment: 'development',
            keyId: input.keyId,
            publicKey: `attestation-public-key:${input.keyId}`,
        };
    },
};

export function createTestAuth(): NonNullable<CreateAppOptions['auth']> {
    return {
        config: testConfig,
        store: createMemoryAuthStore(),
        verifiers: {
            appAttest: testAppAttestVerifier,
            passkey: testPasskeyVerifier,
        },
    };
}

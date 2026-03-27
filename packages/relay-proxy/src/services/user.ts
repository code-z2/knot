import type { AuthStore, AppAttestationRecord, UserRecord } from '@/types';

export async function createUser(
    store: AuthStore,
    input: {
        now: number;
        userId: string;
    },
): Promise<UserRecord | null> {
    const user: UserRecord = {
        createdAt: input.now,
        id: input.userId,
        status: 'active',
    };

    return store.createUser(user);
}

export async function getUser(store: AuthStore, id: string) {
    return store.getUser(id);
}

export async function createAttestation(
    store: AuthStore,
    input: {
        environment: AppAttestationRecord['environment'];
        keyId: string;
        now: number;
        publicKey: string;
        signCount: number;
    },
) {
    const attestation: AppAttestationRecord = {
        createdAt: input.now,
        environment: input.environment,
        keyId: input.keyId,
        publicKey: input.publicKey,
        signCount: input.signCount,
        status: 'active',
        updatedAt: input.now,
    };

    return store.createAttestation(attestation);
}

export async function getAttestation(
    store: AuthStore,
    index: { id: 'key_id'; value: string } | { id: 'public_key'; value: string },
) {
    return store.getAttestation(index);
}

export async function updateAttestation(
    store: AuthStore,
    input: {
        keyId: string;
        now: number;
        signCount: number;
    },
) {
    return store.updateAttestation(input.keyId, input.signCount, input.now);
}

import type { AuthStore, PasskeyRecord } from '@/types';

export async function createPasskey(
    store: AuthStore,
    input: {
        counter: number;
        credentialId: string;
        now: number;
        publicKey: string;
        userId: string;
    },
): Promise<PasskeyRecord | null> {
    const passkey: PasskeyRecord = {
        counter: input.counter,
        createdAt: input.now,
        credentialId: input.credentialId,
        publicKey: input.publicKey,
        userId: input.userId,
    };

    return store.createPasskey(passkey);
}

export async function getPasskey(store: AuthStore, credentialId: string) {
    return store.getPasskey(credentialId);
}

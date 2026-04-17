import { ACCESS_TOKEN_TTL_MS } from '@/constants';
import type { AuthStore, SessionRecord } from '@/types';
import { generateToken, generateUUID } from '@/utils';

export async function createSession(
    store: AuthStore,
    input: {
        appAttestKeyId: string;
        now: number;
        userId: `0x${string}`;
    },
): Promise<SessionRecord> {
    const record: SessionRecord = {
        accessToken: generateToken(),
        appAttestKeyId: input.appAttestKeyId,
        expiresAt: input.now + ACCESS_TOKEN_TTL_MS,
        id: generateUUID(),
        issuedAt: input.now,
        refreshToken: generateToken(),
        status: 'active',
        userId: input.userId,
    };

    return store.createSession(record);
}

export async function getSession(store: AuthStore, accessToken: string, now: number): Promise<SessionRecord | null> {
    const session = await store.getSession(accessToken);

    if (!session) {
        return null;
    }

    if (session.status !== 'active' || session.expiresAt <= now) {
        return null;
    }

    return session;
}

export async function revokeSession(store: AuthStore, accessToken: string): Promise<{ ok: boolean }> {
    return store.revokeSession(accessToken);
}

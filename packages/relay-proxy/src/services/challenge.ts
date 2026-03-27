import type { AuthStore, ChallengeKind, ChallengeRecord } from '@/types';
import { CHALLENGE_TTL_SECONDS } from '@/constants';
import { generateUUID, randomChallenge } from '@/utils';

/**
 * Consumes a challenge exactly once and only for the flow kind that issued it.
 */
export async function consumeChallenge(store: AuthStore, id: string, kind: ChallengeKind) {
    return store.consumeChallenge(id, kind);
}

/**
 * Issues a one-time challenge record for register or login verification.
 */
export async function issueChallenge(
    store: AuthStore,
    input: {
        credentialId?: string;
        kind: ChallengeKind;
        userId: string;
    },
): Promise<ChallengeRecord> {
    const record: ChallengeRecord = {
        challenge: randomChallenge(),
        credentialId: input.credentialId ?? null,
        createdAt: Date.now(),
        id: generateUUID(),
        kind: input.kind,
        userId: input.userId,
    };

    return store.storeChallenge(record, CHALLENGE_TTL_SECONDS);
}

import type { AuthStore } from '@/types';
import { MAX_SKEW_MS, NONCE_TTL_SECONDS } from '@/constants';

/**
 * Accepts a request nonce once within the allowed clock-skew window.
 */
export async function consumeNonce(
    store: AuthStore,
    input: {
        appAttestKeyId: string;
        nonce: string;
        now: number;
        timestamp: string;
    },
) {
    const timestamp = Number(input.timestamp);

    if (!Number.isFinite(timestamp)) {
        return false;
    }

    if (Math.abs(input.now - timestamp) > MAX_SKEW_MS) {
        return false;
    }

    return store.consumeNonce(input.appAttestKeyId, input.nonce, NONCE_TTL_SECONDS);
}

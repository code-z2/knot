import { sha256, stringToBytes, toHex } from 'viem';

type BunRuntime = {
    randomUUIDv7?: () => string;
};

export function createKVNonceKey(appAttestKeyId: string, nonce: string) {
    return `nonce:${appAttestKeyId}:${nonce}`;
}

export function createKVChallengeKey(id: string) {
    return `challenge:${id}`;
}

export function parseJsonRecord<type>(value: string | null): type | null {
    if (!value) {
        return null;
    }

    return JSON.parse(value) as type;
}

export function randomChallenge() {
    const bytes = crypto.getRandomValues(new Uint8Array(32));
    return toHex(bytes);
}

export async function buildAppAttestPayload(input: {
    body: string;
    method: string;
    nonce: string;
    path: string;
    timestamp: string;
}) {
    const bodyHash = await sha256(stringToBytes(input.body));

    return JSON.stringify({
        ...input,
        bodyHash,
    });
}

export function generateUUID() {
    const bun = (globalThis as typeof globalThis & { Bun?: BunRuntime }).Bun;

    return bun?.randomUUIDv7?.() ?? crypto.randomUUID();
}

export function generateToken() {
    return `${generateUUID()}${generateUUID()}`.replaceAll('-', '');
}

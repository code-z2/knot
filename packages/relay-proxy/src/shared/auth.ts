/**
 * Request authentication: bearer token + optional HMAC-SHA256 signature verification.
 */
import { bytesToHex } from 'viem';

import { AuthError } from './errors';
import type { Env } from './types';

/**
 * Validates the bearer token and optional HMAC relay signature.
 * @throws AuthError on missing/invalid token or signature.
 */
export async function authorizeRequest(request: Request, env: Env, rawBody: string): Promise<void> {
    const authHeader = (request.headers.get('Authorization') ?? '').trim();
    if (!authHeader.startsWith('Bearer ')) {
        throw new AuthError('Missing bearer token.');
    }

    const token = authHeader.slice('Bearer '.length).trim();
    if (!token || !timingSafeEqual(token, env.RELAY_AUTH_TOKEN.trim())) {
        throw new AuthError('Invalid bearer token.');
    }

    const secret = (env.RELAY_AUTH_HMAC_SECRET ?? '').trim();
    if (!secret) return;

    const timestamp = (request.headers.get('X-Relay-Timestamp') ?? '').trim();
    const signature = (request.headers.get('X-Relay-Signature') ?? '').trim().toLowerCase();
    if (!timestamp || !signature) {
        throw new AuthError('Missing relay signature headers.');
    }

    const parsedTimestamp = Number(timestamp);
    if (!Number.isFinite(parsedTimestamp)) {
        throw new AuthError('Invalid relay timestamp.');
    }

    const now = Math.floor(Date.now() / 1000);
    if (Math.abs(now - Math.floor(parsedTimestamp)) > 300) {
        throw new AuthError('Relay timestamp is outside allowed window.');
    }

    const expected = await hmacHex(secret, `${timestamp}.${rawBody}`);
    if (!timingSafeEqual(signature, expected)) {
        throw new AuthError('Invalid relay signature.');
    }
}

/** Computes HMAC-SHA256 and returns the hex digest (without 0x prefix). */
export async function hmacHex(secret: string, payload: string): Promise<string> {
    const encoder = new TextEncoder();
    const key = await crypto.subtle.importKey(
        'raw',
        encoder.encode(secret),
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['sign'],
    );
    const mac = await crypto.subtle.sign('HMAC', key, encoder.encode(payload));
    return bytesToHex(new Uint8Array(mac)).slice(2);
}

/** Constant-time string comparison to prevent timing attacks. */
export function timingSafeEqual(a: string, b: string): boolean {
    const aBytes = new TextEncoder().encode(a);
    const bBytes = new TextEncoder().encode(b);

    if (aBytes.length !== bBytes.length) return false;

    let diff = 0;
    for (let i = 0; i < aBytes.length; i += 1) {
        diff |= aBytes[i] ^ bBytes[i];
    }
    return diff === 0;
}

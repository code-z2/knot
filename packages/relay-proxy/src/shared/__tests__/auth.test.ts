import { describe, expect, it, vi, beforeEach } from 'vitest';

import { AuthError } from '../errors';
import { authorizeRequest, hmacHex, timingSafeEqual } from '../auth';
import { createMockEnv } from '../../__tests__/mocks';

// ---------------------------------------------------------------------------
// timingSafeEqual
// ---------------------------------------------------------------------------

describe('timingSafeEqual', () => {
    it('returns true for identical strings', () => {
        expect(timingSafeEqual('abc', 'abc')).toBe(true);
    });

    it('returns false for different strings of equal length', () => {
        expect(timingSafeEqual('abc', 'xyz')).toBe(false);
    });

    it('returns false for different lengths', () => {
        expect(timingSafeEqual('short', 'longer')).toBe(false);
    });

    it('returns true for empty strings', () => {
        expect(timingSafeEqual('', '')).toBe(true);
    });
});

// ---------------------------------------------------------------------------
// hmacHex
// ---------------------------------------------------------------------------

describe('hmacHex', () => {
    it('produces deterministic output', async () => {
        const a = await hmacHex('secret', 'payload');
        const b = await hmacHex('secret', 'payload');
        expect(a).toBe(b);
    });

    it('produces different output for different payloads', async () => {
        const a = await hmacHex('secret', 'payload-a');
        const b = await hmacHex('secret', 'payload-b');
        expect(a).not.toBe(b);
    });

    it('produces different output for different secrets', async () => {
        const a = await hmacHex('secret-a', 'payload');
        const b = await hmacHex('secret-b', 'payload');
        expect(a).not.toBe(b);
    });

    it('returns hex string without 0x prefix', async () => {
        const result = await hmacHex('secret', 'data');
        expect(result).toMatch(/^[0-9a-f]{64}$/);
    });
});

// ---------------------------------------------------------------------------
// authorizeRequest
// ---------------------------------------------------------------------------

describe('authorizeRequest', () => {
    const TOKEN = 'test-relay-token';
    let env: ReturnType<typeof createMockEnv>;

    beforeEach(() => {
        env = createMockEnv({ RELAY_AUTH_TOKEN: TOKEN });
    });

    function makeRequest(headers: Record<string, string> = {}): Request {
        return new Request('https://relay.knot.fi/v1/relay', {
            method: 'POST',
            headers,
        });
    }

    it('passes with valid bearer token (no HMAC)', async () => {
        await expect(
            authorizeRequest(makeRequest({ Authorization: `Bearer ${TOKEN}` }), env, '{}'),
        ).resolves.toBeUndefined();
    });

    it('throws on missing Authorization header', async () => {
        await expect(authorizeRequest(makeRequest(), env, '{}')).rejects.toThrow(AuthError);
    });

    it('throws on wrong token', async () => {
        await expect(
            authorizeRequest(makeRequest({ Authorization: 'Bearer wrong-token' }), env, '{}'),
        ).rejects.toThrow(AuthError);
    });

    it('throws on non-Bearer scheme', async () => {
        await expect(
            authorizeRequest(makeRequest({ Authorization: `Basic ${TOKEN}` }), env, '{}'),
        ).rejects.toThrow(AuthError);
    });

    describe('with HMAC enabled', () => {
        const HMAC_SECRET = 'hmac-test-secret';

        beforeEach(() => {
            env = createMockEnv({
                RELAY_AUTH_TOKEN: TOKEN,
                RELAY_AUTH_HMAC_SECRET: HMAC_SECRET,
            });
        });

        it('passes with valid signature', async () => {
            const body = '{"test": true}';
            const now = Math.floor(Date.now() / 1000).toString();
            const sig = await hmacHex(HMAC_SECRET, `${now}.${body}`);

            const request = makeRequest({
                Authorization: `Bearer ${TOKEN}`,
                'X-Relay-Timestamp': now,
                'X-Relay-Signature': sig,
            });

            await expect(authorizeRequest(request, env, body)).resolves.toBeUndefined();
        });

        it('throws on missing signature headers', async () => {
            const request = makeRequest({ Authorization: `Bearer ${TOKEN}` });
            await expect(authorizeRequest(request, env, '{}')).rejects.toThrow(AuthError);
        });

        it('throws on expired timestamp', async () => {
            const body = '{}';
            const oldTimestamp = (Math.floor(Date.now() / 1000) - 600).toString();
            const sig = await hmacHex(HMAC_SECRET, `${oldTimestamp}.${body}`);

            const request = makeRequest({
                Authorization: `Bearer ${TOKEN}`,
                'X-Relay-Timestamp': oldTimestamp,
                'X-Relay-Signature': sig,
            });

            await expect(authorizeRequest(request, env, body)).rejects.toThrow(AuthError);
        });

        it('throws on tampered signature', async () => {
            const body = '{}';
            const now = Math.floor(Date.now() / 1000).toString();

            const request = makeRequest({
                Authorization: `Bearer ${TOKEN}`,
                'X-Relay-Timestamp': now,
                'X-Relay-Signature':
                    '0000000000000000000000000000000000000000000000000000000000000000',
            });

            await expect(authorizeRequest(request, env, body)).rejects.toThrow(AuthError);
        });
    });
});

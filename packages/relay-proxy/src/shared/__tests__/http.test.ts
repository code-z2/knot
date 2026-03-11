import { describe, expect, it } from 'vitest';

import { BadRequestError } from '../errors';
import {
    corsResponse,
    isRouteAllowedForHostname,
    jsonResponse,
    normalizeHostname,
    resolveRequiredEnvValue,
} from '../http';

// ---------------------------------------------------------------------------
// jsonResponse
// ---------------------------------------------------------------------------

describe('jsonResponse', () => {
    it('returns JSON body with default 200 status', async () => {
        const res = jsonResponse({ ok: true });
        expect(res.status).toBe(200);

        const body = await res.json();
        expect(body).toEqual({ ok: true });
    });

    it('respects custom status code', () => {
        const res = jsonResponse({ error: 'nope' }, 400);
        expect(res.status).toBe(400);
    });

    it('sets content-type and cache-control headers', () => {
        const res = jsonResponse({});
        expect(res.headers.get('content-type')).toContain('application/json');
        expect(res.headers.get('cache-control')).toBe('no-store');
    });

    it('includes CORS headers', () => {
        const res = jsonResponse({});
        expect(res.headers.get('access-control-allow-origin')).toBe('*');
    });
});

// ---------------------------------------------------------------------------
// corsResponse
// ---------------------------------------------------------------------------

describe('corsResponse', () => {
    it('adds CORS headers to existing response', () => {
        const raw = new Response('ok', { status: 200 });
        const res = corsResponse(raw);

        expect(res.headers.get('access-control-allow-origin')).toBe('*');
        expect(res.headers.get('access-control-allow-methods')).toContain('POST');
        expect(res.headers.get('access-control-allow-headers')).toContain('authorization');
    });
});

// ---------------------------------------------------------------------------
// normalizeHostname
// ---------------------------------------------------------------------------

describe('normalizeHostname', () => {
    it('lowercases and trims', () => {
        expect(normalizeHostname('  Relay.KNOT.FI  ')).toBe('relay.knot.fi');
    });

    it('strips trailing dots', () => {
        expect(normalizeHostname('relay.knot.fi.')).toBe('relay.knot.fi');
    });
});

// ---------------------------------------------------------------------------
// isRouteAllowedForHostname
// ---------------------------------------------------------------------------

describe('isRouteAllowedForHostname', () => {
    describe('upload.knot.fi', () => {
        const host = 'upload.knot.fi';

        it('allows POST /v1/images/direct-upload', () => {
            expect(isRouteAllowedForHostname(host, 'POST', '/v1/images/direct-upload')).toBe(true);
        });

        it('allows OPTIONS /v1/images/direct-upload', () => {
            expect(isRouteAllowedForHostname(host, 'OPTIONS', '/v1/images/direct-upload')).toBe(
                true,
            );
        });

        it('allows GET /health', () => {
            expect(isRouteAllowedForHostname(host, 'GET', '/health')).toBe(true);
        });

        it('rejects relay routes', () => {
            expect(isRouteAllowedForHostname(host, 'POST', '/v1/relay')).toBe(false);
        });

        it('rejects unknown paths', () => {
            expect(isRouteAllowedForHostname(host, 'GET', '/random')).toBe(false);
        });
    });

    describe('relay.knot.fi', () => {
        const host = 'relay.knot.fi';

        it('allows relay routes', () => {
            expect(isRouteAllowedForHostname(host, 'POST', '/v1/relay')).toBe(true);
        });

        it('blocks upload route', () => {
            expect(isRouteAllowedForHostname(host, 'POST', '/v1/images/direct-upload')).toBe(false);
        });
    });

    describe('non-production hosts', () => {
        it('allows all routes on workers.dev', () => {
            expect(isRouteAllowedForHostname('relay-proxy.workers.dev', 'POST', '/v1/relay')).toBe(
                true,
            );
            expect(
                isRouteAllowedForHostname(
                    'relay-proxy.workers.dev',
                    'POST',
                    '/v1/images/direct-upload',
                ),
            ).toBe(true);
        });

        it('allows all routes on localhost', () => {
            expect(isRouteAllowedForHostname('localhost', 'POST', '/anything')).toBe(true);
        });
    });
});

// ---------------------------------------------------------------------------
// resolveRequiredEnvValue
// ---------------------------------------------------------------------------

describe('resolveRequiredEnvValue', () => {
    it('returns trimmed value', () => {
        expect(resolveRequiredEnvValue('  hello  ', 'VAR')).toBe('hello');
    });

    it('throws on undefined', () => {
        expect(() => resolveRequiredEnvValue(undefined, 'VAR')).toThrow(BadRequestError);
    });

    it('throws on empty string', () => {
        expect(() => resolveRequiredEnvValue('', 'VAR')).toThrow(BadRequestError);
    });

    it('throws on whitespace-only', () => {
        expect(() => resolveRequiredEnvValue('   ', 'VAR')).toThrow(BadRequestError);
    });

    it('includes var name in error', () => {
        expect(() => resolveRequiredEnvValue(undefined, 'MY_KEY')).toThrow('MY_KEY');
    });
});

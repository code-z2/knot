/**
 * HTTP response helpers and hostname-based route control.
 */
import { JSON_HEADERS } from './constants';
import { BadRequestError } from './errors';

export function jsonResponse(payload: unknown, status = 200): Response {
    return corsResponse(
        new Response(JSON.stringify(payload), {
            status,
            headers: JSON_HEADERS,
        }),
    );
}

export function corsResponse(response: Response): Response {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
    response.headers.set(
        'Access-Control-Allow-Headers',
        'authorization,content-type,x-relay-timestamp,x-relay-signature',
    );
    return response;
}

export function normalizeHostname(hostname: string): string {
    return hostname.trim().toLowerCase().replace(/\.+$/, '');
}

export function isRouteAllowedForHostname(hostname: string, method: string, path: string): boolean {
    const upperMethod = method.toUpperCase();

    if (hostname === 'upload.knot.fi') {
        if (path === '/health') return upperMethod === 'GET' || upperMethod === 'OPTIONS';
        if (path === '/v1/images/direct-upload')
            return upperMethod === 'POST' || upperMethod === 'OPTIONS';
        return false;
    }

    if (hostname === 'relay.knot.fi') {
        if (path === '/v1/images/direct-upload') return false;
        return true;
    }

    // Non-production hosts (workers.dev, localhost) keep full routing.
    return true;
}

/**
 * Resolves a required string environment variable.
 * @throws BadRequestError if the value is missing or empty.
 */
export function resolveRequiredEnvValue(value: string | undefined, name: string): string {
    const trimmed = (value ?? '').trim();
    if (!trimmed) {
        throw new BadRequestError(`Missing required env var: ${name}`);
    }
    return trimmed;
}

import { SUPPORT_MODES } from '../shared/constants';
import { BadRequestError } from '../shared/errors';
import { jsonResponse } from '../shared/http';
import type { Env, SingletonConfig, SupportMode } from '../shared/types';

export function handleSingletonVersion(url: URL, env: Env): Response {
    const modeRaw = (url.searchParams.get('supportMode') ?? '').trim();
    if (!SUPPORT_MODES.has(modeRaw as SupportMode)) {
        throw new BadRequestError('Missing or invalid supportMode.');
    }

    const supportMode = modeRaw as SupportMode;
    const config = parseSingletonConfig(env);
    const entry = config?.[supportMode];

    if (!entry?.address || !entry.accumulatorFactory || !entry.version) {
        return jsonResponse({ ok: false, error: 'singleton_not_configured' }, 503);
    }

    return jsonResponse({ ok: true, ...entry });
}

function parseSingletonConfig(env: Env): SingletonConfig | undefined {
    const raw = (env.SINGLETON_CONFIG ?? '').trim();
    if (!raw) return undefined;

    try {
        return JSON.parse(raw) as SingletonConfig;
    } catch {
        return undefined;
    }
}

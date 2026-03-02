import type { Env } from "./relay/models";
import { jsonResponse } from "./utils";

export function handleSingletonVersion(env: Env): Response {
    const address = (env.SINGLETON_ADDRESS ?? "").trim();
    const accumulatorFactory = (env.SINGLETON_ACCUMULATOR_FACTORY ?? "").trim();
    const version = (env.SINGLETON_VERSION ?? "").trim();
    const releaseNotes = (env.SINGLETON_RELEASE_NOTES ?? "").trim();

    if (!address || !accumulatorFactory || !version) {
        return jsonResponse({ ok: false, error: "singleton_not_configured" }, 503);
    }

    return jsonResponse({
        ok: true,
        currentSingleton: address.toLowerCase(),
        accumulatorFactory: accumulatorFactory.toLowerCase(),
        version,
        releaseNotes: releaseNotes || undefined,
    });
}

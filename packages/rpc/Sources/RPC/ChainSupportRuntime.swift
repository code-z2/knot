import Foundation

public enum ChainSupportRuntime {
    private static let modeOverrideDefaultsKey = "chain_support_mode_override"

    public static func setPreferredMode(
        _ mode: ChainSupportMode?,
        defaults: UserDefaults = .standard,
    ) {
        if let mode {
            defaults.set(mode.rawValue, forKey: modeOverrideDefaultsKey)
        } else {
            defaults.removeObject(forKey: modeOverrideDefaultsKey)
        }
    }

    public static func preferredMode(
        defaults: UserDefaults = .standard,
    ) -> ChainSupportMode? {
        guard let rawMode = defaults.string(forKey: modeOverrideDefaultsKey) else {
            return nil
        }

        return ChainSupportMode(rawValue: rawMode)
    }

    public static func resolveMode(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
    ) -> ChainSupportMode {
        if let preferred = preferredMode(defaults: defaults) {
            return preferred
        }

        let rawMode =
            resolveSetting(
                key: "CHAIN_SUPPORT_MODE",
                bundle: bundle,
            ) ?? ChainSupportMode.limitedTestnet.rawValue

        return ChainSupportMode(rawValue: rawMode) ?? .limitedTestnet
    }

    public static func resolveSupportedChainIDs(
        mode: ChainSupportMode? = nil,
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
    ) -> [UInt64] {
        let resolvedMode = mode ?? resolveMode(bundle: bundle, defaults: defaults)
        guard let rawValue = resolveSetting(key: resolvedMode.supportedChainsKey, bundle: bundle) else {
            return resolvedMode.defaultChainIDs
        }

        var output: [UInt64] = []
        var seen = Set<UInt64>()
        for token in rawValue.split(separator: ",") {
            guard let chainID = UInt64(token.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                continue
            }

            if seen.insert(chainID).inserted {
                output.append(chainID)
            }
        }

        return output.isEmpty ? resolvedMode.defaultChainIDs : output
    }

    public static func resolveConfig(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
    ) -> ChainSupportConfigModel {
        let mode = resolveMode(bundle: bundle, defaults: defaults)
        let chainIDs = resolveSupportedChainIDs(mode: mode, bundle: bundle, defaults: defaults)
        return ChainSupportConfigModel(mode: mode, chainIDs: chainIDs)
    }

    private static func resolveSetting(
        key: String,
        bundle: Bundle,
    ) -> String? {
        if let plist = bundle.object(forInfoDictionaryKey: key) as? String {
            let trimmed = plist.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }
}

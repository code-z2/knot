import Foundation

public enum ChainSupportMode: String, Sendable {
    case limitedTestnet = "LIMITED_TESTNET"
    case limitedMainnet = "LIMITED_MAINNET"
    case fullMainnet = "FULL_MAINNET"

    public var supportedChainsKey: String {
        switch self {
        case .limitedTestnet:
            "SUPPORTED_CHAINS_LIMITED_TESTNET"
        case .limitedMainnet:
            "SUPPORTED_CHAINS_LIMITED_MAINNET"
        case .fullMainnet:
            "SUPPORTED_CHAINS_FULL_MAINNET"
        }
    }

    public var defaultChainIDs: [UInt64] {
        switch self {
        case .limitedTestnet:
            [11_155_111, 84532, 421_614]
        case .limitedMainnet:
            [1, 42161, 8453, 137, 143]
        case .fullMainnet:
            [1, 10, 137, 8453, 42161, 143]
        }
    }
}

public struct ChainSupportConfig: Sendable, Equatable {
    public let mode: ChainSupportMode
    public let chainIDs: [UInt64]

    public init(mode: ChainSupportMode, chainIDs: [UInt64]) {
        self.mode = mode
        self.chainIDs = chainIDs
    }
}

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
    ) -> ChainSupportConfig {
        let mode = resolveMode(bundle: bundle, defaults: defaults)
        let chainIDs = resolveSupportedChainIDs(mode: mode, bundle: bundle, defaults: defaults)
        return ChainSupportConfig(mode: mode, chainIDs: chainIDs)
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

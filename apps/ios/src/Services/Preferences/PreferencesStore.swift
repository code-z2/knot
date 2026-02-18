import Foundation
import Observation
import RPC

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case dark
    case system
    case light

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .dark: "Dark"
        case .system: "System"
        case .light: "Light"
        }
    }
}

struct CurrencyOption: Identifiable, Equatable, Sendable {
    let code: String
    let name: String
    let iconAssetName: String

    var id: String {
        code
    }
}

struct LanguageOption: Identifiable, Equatable, Sendable {
    let code: String
    let displayName: String
    let flag: String

    var id: String {
        code
    }

    var listLabel: String {
        "\(flag) \(displayName)"
    }
}

@MainActor
@Observable
final class PreferencesStore {
    private enum Key {
        static let selectedCurrencyCode = "prefs.selectedCurrencyCode"
        static let hasExplicitCurrencySelection = "prefs.hasExplicitCurrencySelection"
        static let hapticsEnabled = "prefs.hapticsEnabled"
        static let languageCode = "prefs.languageCode"
        static let appearance = "prefs.appearance"
        static let chainSupportMode = "prefs.chainSupportMode"
    }

    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private var suppressCurrencyTracking = false
    private(set) var supportedCurrencies: [CurrencyOption]
    private(set) var supportedLanguages: [LanguageOption]
    private(set) var hasExplicitCurrencySelection: Bool {
        didSet { defaults.set(hasExplicitCurrencySelection, forKey: Key.hasExplicitCurrencySelection) }
    }

    var selectedCurrencyCode: String {
        didSet {
            let normalized = PreferencesStore.normalizeCurrencyCode(selectedCurrencyCode, supported: supportedCurrencies)
            if selectedCurrencyCode != normalized {
                selectedCurrencyCode = normalized
                return
            }
            defaults.set(normalized, forKey: Key.selectedCurrencyCode)
            if !suppressCurrencyTracking {
                hasExplicitCurrencySelection = true
            }
        }
    }

    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }

    var languageCode: String {
        didSet {
            let normalized = PreferencesStore.normalizeLanguageCode(languageCode, supported: supportedLanguages)
            if languageCode != normalized {
                languageCode = normalized
                return
            }
            defaults.set(normalized, forKey: Key.languageCode)
            autoApplyCurrencyFromLanguageIfNeeded()
        }
    }

    var appearance: AppAppearance {
        didSet {
            let normalized = PreferencesStore.normalizeAppearance(appearance)
            if appearance != normalized {
                appearance = normalized
                return
            }
            defaults.set(normalized.rawValue, forKey: Key.appearance)
        }
    }

    var chainSupportMode: ChainSupportMode {
        didSet {
            let normalized = PreferencesStore.normalizeChainSupportMode(chainSupportMode)
            if chainSupportMode != normalized {
                chainSupportMode = normalized
                return
            }
            defaults.set(normalized.rawValue, forKey: Key.chainSupportMode)
            ChainSupportRuntime.setPreferredMode(normalized, defaults: defaults)
        }
    }

    init(
        defaults: UserDefaults = .standard,
        supportedCurrencies: [CurrencyOption] = PreferencesStore.defaultCurrencies,
        supportedLanguages: [LanguageOption] = PreferencesStore.defaultLanguages,
    ) {
        self.defaults = defaults
        self.supportedCurrencies = supportedCurrencies
        self.supportedLanguages = supportedLanguages

        let storedLanguage = defaults.string(forKey: Key.languageCode)
        let resolvedLanguage = PreferencesStore.resolveLanguageCode(
            stored: storedLanguage,
            supported: supportedLanguages,
            fallback: PreferencesStore.defaultLanguageCode,
        )

        let storedCurrency = defaults.string(forKey: Key.selectedCurrencyCode)
        if defaults.object(forKey: Key.hasExplicitCurrencySelection) == nil {
            hasExplicitCurrencySelection = storedCurrency != nil
        } else {
            hasExplicitCurrencySelection = defaults.bool(forKey: Key.hasExplicitCurrencySelection)
        }
        if let storedCurrency {
            selectedCurrencyCode = PreferencesStore.normalizeCurrencyCode(storedCurrency, supported: supportedCurrencies)
        } else {
            selectedCurrencyCode = PreferencesStore.suggestedCurrencyCode(
                forLanguageCode: resolvedLanguage,
                supported: supportedCurrencies,
            )
        }

        if defaults.object(forKey: Key.hapticsEnabled) == nil {
            hapticsEnabled = true
        } else {
            hapticsEnabled = defaults.bool(forKey: Key.hapticsEnabled)
        }

        languageCode = resolvedLanguage

        let storedAppearance = defaults.string(forKey: Key.appearance)
        appearance = PreferencesStore.resolveAppearance(storedAppearance)

        let storedMode = defaults.string(forKey: Key.chainSupportMode)
        let resolvedMode = PreferencesStore.resolveChainSupportMode(
            stored: storedMode,
            fallback: ChainSupportRuntime.resolveMode(defaults: defaults),
        )
        chainSupportMode = resolvedMode
        ChainSupportRuntime.setPreferredMode(resolvedMode, defaults: defaults)
    }

    func updateSupportedCurrencies(_ currencies: [CurrencyOption]) {
        supportedCurrencies = currencies
        if hasExplicitCurrencySelection {
            let normalized = PreferencesStore.normalizeCurrencyCode(selectedCurrencyCode, supported: currencies)
            if selectedCurrencyCode != normalized {
                selectedCurrencyCode = normalized
            }
        } else {
            let suggested = PreferencesStore.suggestedCurrencyCode(
                forLanguageCode: languageCode,
                supported: currencies,
            )
            if selectedCurrencyCode != suggested {
                suppressCurrencyTracking = true
                selectedCurrencyCode = suggested
                suppressCurrencyTracking = false
            }
        }
    }

    func updateSupportedLanguages(_ languages: [LanguageOption]) {
        supportedLanguages = languages
        let normalized = PreferencesStore.normalizeLanguageCode(languageCode, supported: languages)
        if languageCode != normalized {
            languageCode = normalized
        }
    }

    var selectedCurrency: CurrencyOption? {
        supportedCurrencies.first(where: { $0.code == selectedCurrencyCode })
    }

    var selectedLanguage: LanguageOption? {
        supportedLanguages.first(where: { $0.code == languageCode })
    }

    var locale: Locale {
        Locale(identifier: languageCode)
    }

    private static func normalizeCurrencyCode(_ code: String, supported: [CurrencyOption]) -> String {
        let normalized = code.uppercased()
        if supported.map(\.code).contains(normalized) { return normalized }
        return supported.first?.code ?? "USD"
    }

    private static func normalizeLanguageCode(_ code: String, supported: [LanguageOption]) -> String {
        let normalized = code.lowercased()
        if supported.map(\.code).contains(normalized) { return normalized }
        return resolveLanguageCode(stored: nil, supported: supported, fallback: defaultLanguageCode)
    }

    private static func normalizeAppearance(_ appearance: AppAppearance) -> AppAppearance {
        appearance
    }

    private static func resolveAppearance(_ rawValue: String?) -> AppAppearance {
        guard let rawValue else { return .dark }
        return AppAppearance(rawValue: rawValue) ?? .dark
    }

    private static func normalizeChainSupportMode(_ mode: ChainSupportMode) -> ChainSupportMode {
        mode
    }

    private static func resolveChainSupportMode(
        stored: String?,
        fallback: ChainSupportMode,
    ) -> ChainSupportMode {
        guard let stored else { return fallback }
        return ChainSupportMode(rawValue: stored) ?? fallback
    }

    private static func resolveLanguageCode(
        stored: String?,
        supported: [LanguageOption],
        fallback: String,
    ) -> String {
        let supportedCodes = supported.map(\.code)
        if let stored, supportedCodes.contains(stored.lowercased()) {
            return stored.lowercased()
        }

        for systemLanguage in Locale.preferredLanguages {
            let normalized = systemLanguage.lowercased()
            if supportedCodes.contains(normalized) {
                return normalized
            }
            if let base = normalized.split(separator: "-").first,
               supportedCodes.contains(String(base))
            {
                return String(base)
            }
        }

        return supportedCodes.contains(fallback) ? fallback : (supportedCodes.first ?? "en")
    }

    private static func suggestedCurrencyCode(
        forLanguageCode languageCode: String,
        supported: [CurrencyOption],
    ) -> String {
        let normalizedLanguage = languageCode.lowercased()
        let suggestedByLanguage: [String: String] = [
            "ar": "USD",
            "bn": "USD",
            "de": "EUR",
            "en": "USD",
            "es": "EUR",
            "fr": "EUR",
            "hi": "INR",
            "it": "EUR",
            "ja": "JPY",
            "jv": "USD",
            "ko": "KRW",
            "mr": "INR",
            "pt": "BRL",
            "ru": "RUB",
            "sw": "USD",
            "ta": "INR",
            "te": "INR",
            "tr": "USD",
            "ur": "INR",
            "zh": "CNY",
        ]

        if let mapped = suggestedByLanguage[normalizedLanguage] {
            return normalizeCurrencyCode(mapped, supported: supported)
        }
        return normalizeCurrencyCode("USD", supported: supported)
    }

    private func autoApplyCurrencyFromLanguageIfNeeded() {
        guard !hasExplicitCurrencySelection else { return }
        let suggested = PreferencesStore.suggestedCurrencyCode(
            forLanguageCode: languageCode,
            supported: supportedCurrencies,
        )
        guard selectedCurrencyCode != suggested else { return }
        suppressCurrencyTracking = true
        selectedCurrencyCode = suggested
        suppressCurrencyTracking = false
    }

    nonisolated static let defaultLanguageCode = "en"

    nonisolated static let defaultCurrencies: [CurrencyOption] = [
        .init(code: "EUR", name: "european euro", iconAssetName: "eurosign"),
        .init(code: "GBP", name: "british pounds", iconAssetName: "sterlingsign"),
        .init(code: "NGN", name: "nigerian naira", iconAssetName: "nairasign"),
        .init(code: "USD", name: "united states dollar", iconAssetName: "dollarsign"),
        .init(code: "JPY", name: "japanese yen", iconAssetName: "yensign"),
        .init(code: "INR", name: "indian rupee", iconAssetName: "indianrupeesign"),
        .init(code: "RUB", name: "russian ruble", iconAssetName: "rublesign"),
        .init(code: "BRL", name: "brazillian real", iconAssetName: "brazilianrealsign"),
        .init(code: "ARS", name: "argentinian peso", iconAssetName: "pesosign"),
        .init(code: "CNY", name: "chinese yuan", iconAssetName: "chineseyuanrenminbisign"),
        .init(code: "GHS", name: "ghanian cedi", iconAssetName: "cedisign"),
        .init(code: "KRW", name: "korean won", iconAssetName: "wonsign"),
    ]

    nonisolated static let defaultLanguages: [LanguageOption] = [
        .init(code: "ar", displayName: "Arabic", flag: "🇸🇦"),
        .init(code: "bn", displayName: "Bengali", flag: "🇧🇩"),
        .init(code: "zh", displayName: "Chinese", flag: "🇨🇳"),
        .init(code: "en", displayName: "English", flag: "🇺🇸"),
        .init(code: "fr", displayName: "French", flag: "🇫🇷"),
        .init(code: "de", displayName: "German", flag: "🇩🇪"),
        .init(code: "hi", displayName: "Hindi", flag: "🇮🇳"),
        .init(code: "it", displayName: "Italian", flag: "🇮🇹"),
        .init(code: "ja", displayName: "Japanese", flag: "🇯🇵"),
        .init(code: "jv", displayName: "Javanese", flag: "🇮🇩"),
        .init(code: "ko", displayName: "Korean", flag: "🇰🇷"),
        .init(code: "mr", displayName: "Marathi", flag: "🇮🇳"),
        .init(code: "pt", displayName: "Portuguese (Brazil)", flag: "🇧🇷"),
        .init(code: "ru", displayName: "Russian", flag: "🇷🇺"),
        .init(code: "es", displayName: "Spanish", flag: "🇪🇸"),
        .init(code: "sw", displayName: "Swahili", flag: "🇰🇪"),
        .init(code: "ta", displayName: "Tamil", flag: "🇱🇰"),
        .init(code: "te", displayName: "Telugu", flag: "🇮🇳"),
        .init(code: "tr", displayName: "Turkish", flag: "🇹🇷"),
        .init(code: "ur", displayName: "Urdu", flag: "🇵🇰"),
    ]
}

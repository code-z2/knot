import Foundation
import Observation

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case dark
    case system
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .system: return "System"
        case .light: return "Light"
        }
    }
}

struct CurrencyOption: Identifiable, Equatable, Sendable {
    let code: String
    let name: String
    let iconAssetName: String

    var id: String { code }
}

struct LanguageOption: Identifiable, Equatable, Sendable {
    let code: String
    let displayName: String
    let flag: String

    var id: String { code }

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

    init(
        defaults: UserDefaults = .standard,
        supportedCurrencies: [CurrencyOption] = PreferencesStore.defaultCurrencies,
        supportedLanguages: [LanguageOption] = PreferencesStore.defaultLanguages
    ) {
        self.defaults = defaults
        self.supportedCurrencies = supportedCurrencies
        self.supportedLanguages = supportedLanguages

        let storedLanguage = defaults.string(forKey: Key.languageCode)
        let resolvedLanguage = PreferencesStore.resolveLanguageCode(
            stored: storedLanguage,
            supported: supportedLanguages,
            fallback: PreferencesStore.defaultLanguageCode
        )

        let storedCurrency = defaults.string(forKey: Key.selectedCurrencyCode)
        if defaults.object(forKey: Key.hasExplicitCurrencySelection) == nil {
            self.hasExplicitCurrencySelection = storedCurrency != nil
        } else {
            self.hasExplicitCurrencySelection = defaults.bool(forKey: Key.hasExplicitCurrencySelection)
        }
        if let storedCurrency {
            self.selectedCurrencyCode = PreferencesStore.normalizeCurrencyCode(storedCurrency, supported: supportedCurrencies)
        } else {
            self.selectedCurrencyCode = PreferencesStore.suggestedCurrencyCode(
                forLanguageCode: resolvedLanguage,
                supported: supportedCurrencies
            )
        }

        if defaults.object(forKey: Key.hapticsEnabled) == nil {
            self.hapticsEnabled = true
        } else {
            self.hapticsEnabled = defaults.bool(forKey: Key.hapticsEnabled)
        }

        self.languageCode = resolvedLanguage

        let storedAppearance = defaults.string(forKey: Key.appearance)
        self.appearance = PreferencesStore.resolveAppearance(storedAppearance)
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
                supported: currencies
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
        let normalized = normalizeLegacyCurrencyCode(code.uppercased())
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

    private static func resolveLanguageCode(
        stored: String?,
        supported: [LanguageOption],
        fallback: String
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
               supportedCodes.contains(String(base)) {
                return String(base)
            }
        }

        return supportedCodes.contains(fallback) ? fallback : (supportedCodes.first ?? "en")
    }

    private static func suggestedCurrencyCode(
        forLanguageCode languageCode: String,
        supported: [CurrencyOption]
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
            "ko": "USD",
            "mr": "INR",
            "pt": "EUR",
            "ru": "RUB",
            "sw": "USD",
            "ta": "INR",
            "te": "INR",
            "tr": "USD",
            "ur": "INR",
        ]

        if let mapped = suggestedByLanguage[normalizedLanguage] {
            return normalizeCurrencyCode(mapped, supported: supported)
        }
        return normalizeCurrencyCode("USD", supported: supported)
    }

    private static func normalizeLegacyCurrencyCode(_ code: String) -> String {
        switch code {
        case "YEN":
            return "JPY"
        case "SUR":
            return "RUB"
        default:
            return code
        }
    }

    private func autoApplyCurrencyFromLanguageIfNeeded() {
        guard !hasExplicitCurrencySelection else { return }
        let suggested = PreferencesStore.suggestedCurrencyCode(
            forLanguageCode: languageCode,
            supported: supportedCurrencies
        )
        guard selectedCurrencyCode != suggested else { return }
        suppressCurrencyTracking = true
        selectedCurrencyCode = suggested
        suppressCurrencyTracking = false
    }

    nonisolated static let defaultLanguageCode = "en"

    nonisolated static let defaultCurrencies: [CurrencyOption] = [
        .init(code: "ETH", name: "ethereum", iconAssetName: "Icons/currency_ethereum_circle"),
        .init(code: "EUR", name: "european euro", iconAssetName: "Icons/currency_euro_circle"),
        .init(code: "GBP", name: "british pounds", iconAssetName: "Icons/currency_pound_circle"),
        .init(code: "NGN", name: "nigerian naira", iconAssetName: "Icons/currency_dollar_circle"),
        .init(code: "USD", name: "united states dollar", iconAssetName: "Icons/currency_dollar_circle"),
        .init(code: "JPY", name: "japanese yen", iconAssetName: "Icons/currency_yen_circle"),
        .init(code: "INR", name: "indian rupee", iconAssetName: "Icons/currency_rupee_circle"),
        .init(code: "RUB", name: "russian ruble", iconAssetName: "Icons/currency_ruble_circle"),
    ]

    nonisolated static let defaultLanguages: [LanguageOption] = [
        .init(code: "ar", displayName: "Arabic", flag: "🇸🇦"),
        .init(code: "bn", displayName: "Bengali", flag: "🇧🇩"),
        .init(code: "en", displayName: "English", flag: "🇬🇧"),
        .init(code: "fr", displayName: "French", flag: "🇫🇷"),
        .init(code: "de", displayName: "German", flag: "🇩🇪"),
        .init(code: "hi", displayName: "Hindi", flag: "🇮🇳"),
        .init(code: "it", displayName: "Italian", flag: "🇮🇹"),
        .init(code: "ja", displayName: "Japanese", flag: "🇯🇵"),
        .init(code: "jv", displayName: "Javanese", flag: "🇮🇩"),
        .init(code: "ko", displayName: "Korean", flag: "🇰🇷"),
        .init(code: "mr", displayName: "Marathi", flag: "🇮🇳"),
        .init(code: "pt", displayName: "Portuguese", flag: "🇵🇹"),
        .init(code: "ru", displayName: "Russian", flag: "🇷🇺"),
        .init(code: "es", displayName: "Spanish", flag: "🇪🇸"),
        .init(code: "sw", displayName: "Swahili", flag: "🇰🇪"),
        .init(code: "ta", displayName: "Tamil", flag: "🇱🇰"),
        .init(code: "te", displayName: "Telugu", flag: "🇮🇳"),
        .init(code: "tr", displayName: "Turkish", flag: "🇹🇷"),
        .init(code: "ur", displayName: "Urdu", flag: "🇵🇰"),
    ]
}

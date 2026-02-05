import Foundation
import Observation

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
        static let hapticsEnabled = "prefs.hapticsEnabled"
        static let languageCode = "prefs.languageCode"
    }

    @ObservationIgnored
    private let defaults: UserDefaults
    private(set) var supportedCurrencies: [CurrencyOption]
    private(set) var supportedLanguages: [LanguageOption]

    var selectedCurrencyCode: String {
        didSet {
            let normalized = PreferencesStore.normalizeCurrencyCode(selectedCurrencyCode, supported: supportedCurrencies)
            if selectedCurrencyCode != normalized {
                selectedCurrencyCode = normalized
                return
            }
            defaults.set(normalized, forKey: Key.selectedCurrencyCode)
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

        let storedCurrency = defaults.string(forKey: Key.selectedCurrencyCode)
        self.selectedCurrencyCode = PreferencesStore.normalizeCurrencyCode(storedCurrency ?? "USD", supported: supportedCurrencies)

        if defaults.object(forKey: Key.hapticsEnabled) == nil {
            self.hapticsEnabled = true
        } else {
            self.hapticsEnabled = defaults.bool(forKey: Key.hapticsEnabled)
        }

        let storedLanguage = defaults.string(forKey: Key.languageCode)
        self.languageCode = PreferencesStore.resolveLanguageCode(
            stored: storedLanguage,
            supported: supportedLanguages,
            fallback: PreferencesStore.defaultLanguageCode
        )
    }

    func updateSupportedCurrencies(_ currencies: [CurrencyOption]) {
        supportedCurrencies = currencies
        let normalized = PreferencesStore.normalizeCurrencyCode(selectedCurrencyCode, supported: currencies)
        if selectedCurrencyCode != normalized {
            selectedCurrencyCode = normalized
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

    nonisolated static let defaultLanguageCode = "en"

    nonisolated static let defaultCurrencies: [CurrencyOption] = [
        .init(code: "ETH", name: "ethereum", iconAssetName: "Icons/currency_ethereum_circle"),
        .init(code: "EUR", name: "european euro", iconAssetName: "Icons/currency_euro_circle"),
        .init(code: "GBP", name: "british pounds", iconAssetName: "Icons/currency_pound_circle"),
        .init(code: "USD", name: "united states dollar", iconAssetName: "Icons/currency_dollar_circle"),
        .init(code: "YEN", name: "chinese yen", iconAssetName: "Icons/currency_yen_circle"),
        .init(code: "INR", name: "indian rupee", iconAssetName: "Icons/currency_rupee_circle"),
        .init(code: "SUR", name: "soviet rubble", iconAssetName: "Icons/currency_ruble_circle"),
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

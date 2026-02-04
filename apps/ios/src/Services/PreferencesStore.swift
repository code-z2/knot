import Foundation

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
final class PreferencesStore {
  private enum Key {
    static let selectedCurrencyCode = "prefs.selectedCurrencyCode"
    static let hapticsEnabled = "prefs.hapticsEnabled"
    static let languageCode = "prefs.languageCode"
  }

  private let defaults: UserDefaults
  private(set) var supportedCurrencies: [CurrencyOption]
  private(set) var supportedLanguages: [LanguageOption]

  init(
    defaults: UserDefaults = .standard,
    supportedCurrencies: [CurrencyOption] = PreferencesStore.defaultCurrencies,
    supportedLanguages: [LanguageOption] = PreferencesStore.defaultLanguages
  ) {
    self.defaults = defaults
    self.supportedCurrencies = supportedCurrencies
    self.supportedLanguages = supportedLanguages
  }

  var selectedCurrencyCode: String {
    get {
      let stored = defaults.string(forKey: Key.selectedCurrencyCode)
      let valid = supportedCurrencies.map(\.code)
      if let stored, valid.contains(stored) { return stored }
      return "USD"
    }
    set {
      defaults.set(newValue.uppercased(), forKey: Key.selectedCurrencyCode)
    }
  }

  var hapticsEnabled: Bool {
    get {
      if defaults.object(forKey: Key.hapticsEnabled) == nil { return true }
      return defaults.bool(forKey: Key.hapticsEnabled)
    }
    set { defaults.set(newValue, forKey: Key.hapticsEnabled) }
  }

  var languageCode: String {
    get {
      let stored = defaults.string(forKey: Key.languageCode)
      let valid = supportedLanguages.map(\.code)
      if let stored, valid.contains(stored.lowercased()) { return stored.lowercased() }
      return "english"
    }
    set { defaults.set(newValue.lowercased(), forKey: Key.languageCode) }
  }

  func updateSupportedCurrencies(_ currencies: [CurrencyOption]) {
    supportedCurrencies = currencies
    if !currencies.map(\.code).contains(selectedCurrencyCode) {
      selectedCurrencyCode = currencies.first?.code ?? "USD"
    }
  }

  func updateSupportedLanguages(_ languages: [LanguageOption]) {
    supportedLanguages = languages
    if !languages.map(\.code).contains(languageCode) {
      languageCode = languages.first?.code ?? "english"
    }
  }

  var selectedCurrency: CurrencyOption? {
    supportedCurrencies.first(where: { $0.code == selectedCurrencyCode })
  }

  var selectedLanguage: LanguageOption? {
    supportedLanguages.first(where: { $0.code == languageCode })
  }

  static let defaultCurrencies: [CurrencyOption] = [
    .init(code: "ETH", name: "ethereum", iconAssetName: "Icons/currency_ethereum_circle"),
    .init(code: "EUR", name: "european euro", iconAssetName: "Icons/currency_euro_circle"),
    .init(code: "GBP", name: "british pounds", iconAssetName: "Icons/currency_pound_circle"),
    .init(code: "USD", name: "united states dollar", iconAssetName: "Icons/currency_dollar_circle"),
    .init(code: "YEN", name: "chinese yen", iconAssetName: "Icons/currency_yen_circle"),
    .init(code: "INR", name: "indian rupee", iconAssetName: "Icons/currency_rupee_circle"),
    .init(code: "SUR", name: "soviet rubble", iconAssetName: "Icons/currency_ruble_circle"),
  ]

  static let defaultLanguages: [LanguageOption] = [
    .init(code: "arabic", displayName: "Arabic", flag: "🇸🇦"),
    .init(code: "bengali", displayName: "Bengali", flag: "🇧🇩"),
    .init(code: "english", displayName: "English", flag: "🇬🇧"),
    .init(code: "french", displayName: "French", flag: "🇫🇷"),
    .init(code: "german", displayName: "German", flag: "🇩🇪"),
    .init(code: "hindi", displayName: "Hindi", flag: "🇮🇳"),
    .init(code: "italian", displayName: "Italian", flag: "🇮🇹"),
    .init(code: "japanese", displayName: "Japanese", flag: "🇯🇵"),
    .init(code: "javanese", displayName: "Javanese", flag: "🇮🇩"),
    .init(code: "korean", displayName: "Korean", flag: "🇰🇷"),
    .init(code: "marathi", displayName: "Marathi", flag: "🇮🇳"),
    .init(code: "portuguese", displayName: "Portuguese", flag: "🇵🇹"),
    .init(code: "russian", displayName: "Russian", flag: "🇷🇺"),
    .init(code: "spanish", displayName: "Spanish", flag: "🇪🇸"),
    .init(code: "swahili", displayName: "Swahili", flag: "🇰🇪"),
    .init(code: "tamil", displayName: "Tamil", flag: "🇱🇰"),
    .init(code: "telugu", displayName: "Telugu", flag: "🇮🇳"),
    .init(code: "turkish", displayName: "Turkish", flag: "🇹🇷"),
    .init(code: "urdu", displayName: "Urdu", flag: "🇵🇰"),
  ]
}

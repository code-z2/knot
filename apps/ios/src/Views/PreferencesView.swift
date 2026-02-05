import Observation
import SwiftUI

struct PreferencesView: View {
  @Bindable var preferencesStore: PreferencesStore
  var onBack: () -> Void = {}
  @State private var showCurrencySheet = false
  @State private var showLanguageSheet = false

  var body: some View {
    ZStack {
      AppThemeColor.fixedDarkSurface.ignoresSafeArea()

      VStack(spacing: 0) {
        VStack(spacing: 12) {
          PreferenceRow(
            title: "preferences_appearance",
            iconName: "Icons/lightbulb_02",
            trailing: .chevron
          )
          PreferenceRow(
            title: "preferences_haptics",
            iconName: "Icons/vibration",
            trailing: .toggle(isOn: $preferencesStore.hapticsEnabled)
          )
          PreferenceRow(
            title: "preferences_currency",
            iconName: "Icons/bank_note_03",
            trailing: .valueChevron(preferencesStore.selectedCurrencyCode.lowercased()),
            action: { showCurrencySheet = true }
          )
          PreferenceRow(
            title: "preferences_language",
            iconName: "Icons/translate_01",
            trailing: .valueChevron(
              preferencesStore.selectedLanguage?.displayName ?? preferencesStore.languageCode),
            action: { showLanguageSheet = true }
          )
          // PreferenceRow(
          //     title: "preferences_business",
          //     iconName: "Icons/building_02",
          //     trailing: .chevron
          // )
        }
        .padding(.top, AppHeaderMetrics.contentTopPadding)
        .padding(.horizontal, 20)

        Spacer()
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      AppHeader(
        title: "preferences_title",
        titleFont: .custom("Roboto-Bold", size: 22),
        titleColor: AppThemeColor.labelSecondary,
        onBack: onBack
      )
    }
    .sheet(isPresented: $showCurrencySheet) {
      CurrencyPickerSheet(
        title: "sheet_currency_title",
        currencies: preferencesStore.supportedCurrencies,
        selectedCode: preferencesStore.selectedCurrencyCode,
        onSelect: { code in
          preferencesStore.selectedCurrencyCode = code
          showCurrencySheet = false
        }
      )
      .presentationDetents([.fraction(0.92)])
      .presentationDragIndicator(.hidden)
      .presentationCornerRadius(40)
    }
    .sheet(isPresented: $showLanguageSheet) {
      LanguagePickerSheet(
        title: "sheet_language_title",
        languages: preferencesStore.supportedLanguages,
        selectedCode: preferencesStore.languageCode,
        onSelect: { code in
          preferencesStore.languageCode = code
          showLanguageSheet = false
        }
      )
      .presentationDetents([.fraction(0.92)])
      .presentationDragIndicator(.hidden)
      .presentationCornerRadius(40)
    }
  }
}

private struct PreferenceRow: View {
  enum Trailing {
    case chevron
    case toggle(isOn: Binding<Bool>)
    case valueChevron(String)
  }

  let title: LocalizedStringKey
  let iconName: String
  let trailing: Trailing
  var action: (() -> Void)? = nil

  var body: some View {
    Group {
      if let action {
        Button(action: action) { rowContent }
          .buttonStyle(.plain)
      } else {
        rowContent
      }
    }
  }

  private var rowContent: some View {
    HStack {
      HStack(spacing: 16) {
        IconBadge(style: .defaultStyle) {
          Image(iconName)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 21, height: 21)
            .foregroundStyle(AppThemeColor.glyphPrimary)
        }

        Text(title)
          .font(.custom("Roboto-Medium", size: 15))
          .foregroundStyle(AppThemeColor.labelPrimary)
      }

      Spacer(minLength: 0)

      switch trailing {
      case .chevron:
        chevron
      case .toggle(let isOn):
        ToggleSwitch(isOn: isOn)
          .padding(.horizontal, 8)
      case .valueChevron(let value):
        HStack(spacing: 10) {
          Text(value)
            .font(.custom("Roboto-Bold", size: 14))
            .underline(true, color: AppThemeColor.labelSecondary)
            .foregroundStyle(AppThemeColor.labelSecondary)
          chevron
        }
      }
    }
    .frame(maxWidth: .infinity, minHeight: 48)
  }

  private var chevron: some View {
    Image("Icons/chevron_right")
      .renderingMode(.template)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(width: 12, height: 12)
      .foregroundStyle(AppThemeColor.glyphSecondary)
      .padding(.horizontal, 8)
  }
}

private struct CurrencyPickerSheet: View {
  let title: LocalizedStringKey
  let currencies: [CurrencyOption]
  let selectedCode: String
  let onSelect: (String) -> Void

  var body: some View {
    ZStack(alignment: .topLeading) {
      AppThemeColor.fixedDarkSurface.ignoresSafeArea()

      RoundedRectangle(cornerRadius: 3.5, style: .continuous)
        .fill(AppThemeColor.gray2)
        .frame(width: 90, height: 5)
        .frame(maxWidth: .infinity)
        .padding(.top, 18)

      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .font(.custom("Roboto-Bold", size: 14))
          .foregroundStyle(AppThemeColor.labelSecondary)
          .padding(.leading, 38)
          .padding(.top, 56)
          .padding(.bottom, 16)

        Rectangle()
          .fill(AppThemeColor.separatorOpaque)
          .frame(height: 4)

        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: 20) {
            ForEach(currencies) { currency in
              CurrencyOptionRow(currency: currency, isSelected: currency.code == selectedCode) {
                onSelect(currency.code)
              }
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 20)
        }
      }
    }
  }
}

private struct CurrencyOptionRow: View {
  let currency: CurrencyOption
  let isSelected: Bool
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 16) {
        IconBadge(style: .neutral) {
          Image(currency.iconAssetName)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 14, height: 14)
            .foregroundStyle(AppThemeColor.accentBrown)
        }
        .frame(width: 26, height: 26)

        VStack(alignment: .leading, spacing: 2) {
          Text(currency.code)
            .font(.custom("Inter-Medium", size: 14))
            .foregroundStyle(AppThemeColor.labelPrimary)
          Text(currency.name)
            .font(.custom("RobotoMono-Medium", size: 12))
            .foregroundStyle(AppThemeColor.labelSecondary)
        }

        Spacer(minLength: 0)

        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(AppThemeColor.accentBrown)
        }
      }
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
    }
    .buttonStyle(.plain)
  }
}

private struct LanguagePickerSheet: View {
  let title: LocalizedStringKey
  let languages: [LanguageOption]
  let selectedCode: String
  let onSelect: (String) -> Void

  var body: some View {
    ZStack(alignment: .topLeading) {
      AppThemeColor.fixedDarkSurface.ignoresSafeArea()

      RoundedRectangle(cornerRadius: 3.5, style: .continuous)
        .fill(AppThemeColor.gray2)
        .frame(width: 90, height: 5)
        .frame(maxWidth: .infinity)
        .padding(.top, 18)

      VStack(alignment: .leading, spacing: 0) {
        Text(title)
          .font(.custom("Roboto-Bold", size: 14))
          .foregroundStyle(AppThemeColor.labelSecondary)
          .padding(.leading, 38)
          .padding(.top, 56)
          .padding(.bottom, 16)

        Rectangle()
          .fill(AppThemeColor.separatorOpaque)
          .frame(height: 4)

        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: 20) {
            ForEach(languages) { language in
              Button {
                onSelect(language.code)
              } label: {
                HStack {
                  Text(language.listLabel)
                    .font(.custom("Inter-Medium", size: 12))
                    .foregroundStyle(AppThemeColor.labelPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                  if language.code == selectedCode {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(AppThemeColor.accentBrown)
                  }
                }
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, 38)
          .padding(.top, 20)
        }
      }
    }
  }
}

#Preview {
  PreferencesView(preferencesStore: PreferencesStore())
}

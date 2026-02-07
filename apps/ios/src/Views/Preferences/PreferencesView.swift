import Observation
import SwiftUI

private enum PreferencesModal {
  case appearance
  case currency
  case language
}

struct PreferencesView: View {
  @Bindable var preferencesStore: PreferencesStore
  var onBack: () -> Void = {}
  @State private var activeModal: PreferencesModal?

  var body: some View {
    ZStack {
      AppThemeColor.backgroundPrimary.ignoresSafeArea()

      VStack(spacing: 0) {
        VStack(spacing: 12) {
          PreferenceRow(
            title: "preferences_appearance",
            iconName: "Icons/lightbulb_02",
            trailing: .valueChevron(preferencesStore.appearance.displayName),
            action: { present(.appearance) }
          )
          PreferenceRow(
            title: "preferences_haptics",
            iconName: "Icons/vibration",
            trailing: .toggle(isOn: $preferencesStore.hapticsEnabled)
          )
          PreferenceRow(
            title: "preferences_currency",
            iconName: "Icons/bank_note_03",
            trailing: .valueChevron(preferencesStore.selectedCurrencyCode.uppercased()),
            action: { present(.currency) }
          )
          PreferenceRow(
            title: "preferences_language",
            iconName: "Icons/translate_01",
            trailing: .valueChevron(
              preferencesStore.selectedLanguage?.displayName ?? preferencesStore.languageCode
            ),
            action: { present(.language) }
          )
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
    .overlay(alignment: .bottom) {
      SlideModal(
        isPresented: activeModal != nil,
        kind: modalKind,
        onDismiss: dismissModal
      ) {
        modalContent
      }
    }
  }

  @ViewBuilder
  private var modalContent: some View {
    switch activeModal {
    case .currency:
      CurrencyPickerModal(
        title: "sheet_currency_title",
        currencies: preferencesStore.supportedCurrencies,
        selectedCode: preferencesStore.selectedCurrencyCode,
        onSelect: { code in
          preferencesStore.selectedCurrencyCode = code
          dismissModalAnimated()
        }
      )
    case .language:
      LanguagePickerModal(
        title: "sheet_language_title",
        languages: preferencesStore.supportedLanguages,
        selectedCode: preferencesStore.languageCode,
        onSelect: { code in
          preferencesStore.languageCode = code
          dismissModalAnimated()
        }
      )
    case .appearance:
      AppearancePickerModal(
        selectedAppearance: preferencesStore.appearance,
        onSelect: { appearance in
          preferencesStore.appearance = appearance
          dismissModalAnimated()
        }
      )
    case .none:
      EmptyView()
    }
  }

  private var modalKind: SlideModalKind {
    switch activeModal {
    case .appearance:
      return .compact(maxHeight: 281, horizontalInset: 0)
    case .currency, .language:
      return .fullHeight(topInset: 12)
    case .none:
      return .fullHeight(topInset: 12)
    }
  }

  private func present(_ modal: PreferencesModal) {
    activeModal = modal
  }

  private func dismissModal() {
    activeModal = nil
  }

  private func dismissModalAnimated() {
    activeModal = nil
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

private struct ModalTitleBar: View {
  let title: LocalizedStringKey

  var body: some View {
    HStack(spacing: 12) {
      Text(title)
        .font(.custom("Roboto-Bold", size: 15))
        .foregroundStyle(AppThemeColor.labelSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 24)
    .padding(.top, 14)
    .padding(.bottom, 16)
  }
}

private struct CurrencyPickerModal: View {
  let title: LocalizedStringKey
  let currencies: [CurrencyOption]
  let selectedCode: String
  let onSelect: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ModalTitleBar(title: title)

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
        .padding(.top, 24)
        .padding(.bottom, 24)
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
            .font(.custom("Inter-Regular_Medium", size: 14))
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

private struct LanguagePickerModal: View {
  let title: LocalizedStringKey
  let languages: [LanguageOption]
  let selectedCode: String
  let onSelect: (String) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ModalTitleBar(title: title)

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
                  .font(.custom("Inter-Regular_Medium", size: 12))
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
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 24)
      }
    }
  }
}

private struct AppearancePickerModal: View {
  let selectedAppearance: AppAppearance
  let onSelect: (AppAppearance) -> Void

  var body: some View {
    HStack(spacing: 36) {
      ForEach(AppAppearance.allCases) { appearance in
        Button {
          onSelect(appearance)
        } label: {
          VStack(spacing: 8) {
            Text(appearance.displayName)
              .font(.custom("RobotoCondensed-Medium", size: 14))
              .foregroundStyle(AppThemeColor.labelPrimary)
              .frame(height: 16)

            AppearancePreviewCard(
              appearance: appearance, isSelected: appearance == selectedAppearance)
          }
        }
        .buttonStyle(.plain)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 36)
    .padding(.bottom, 42)
  }
}

private struct AppearancePreviewCard: View {
  let appearance: AppAppearance
  let isSelected: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 40, style: .continuous)
          .fill(AppThemeColor.gray2Light)
          .frame(width: 12, height: 8)
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(AppThemeColor.gray2Light)
          .frame(width: 32, height: 8)
      }

      RoundedRectangle(cornerRadius: 4, style: .continuous)
        .fill(AppThemeColor.gray2Light)
        .frame(width: 56, height: 22)

      VStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(AppThemeColor.gray2Light)
          .frame(width: 56, height: 8)
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(AppThemeColor.gray2Light)
          .frame(width: 56, height: 8)
      }
    }
    .padding(12)
    .frame(width: 80, height: 94, alignment: .topLeading)
    .background(cardBackground)
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .stroke(
          isSelected ? AppThemeColor.accentBrown : AppThemeColor.separatorOpaque, lineWidth: 1)
    }
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  @ViewBuilder
  private var cardBackground: some View {
    switch appearance {
    case .dark:
      AppThemeColor.grayBlack
    case .system:
      LinearGradient(
        colors: [
          AppThemeColor.grayBlack, AppThemeColor.grayBlack, AppThemeColor.grayWhite,
          AppThemeColor.grayWhite,
        ],
        startPoint: .leading,
        endPoint: .trailing
      )
    case .light:
      AppThemeColor.grayWhite
    }
  }
}

#Preview {
  PreferencesView(preferencesStore: PreferencesStore())
}

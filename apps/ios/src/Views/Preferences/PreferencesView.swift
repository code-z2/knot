import Observation
import RPC
import SwiftUI

private enum PreferencesModal: String, Identifiable {
  case appearance

  var id: String { rawValue }

  var sheetKind: AppSheetKind {
    .height(260)
  }
}

private enum PreferencesPage {
  case main
  case currency
  case language

  var title: LocalizedStringKey {
    switch self {
    case .main:
      return "preferences_title"
    case .currency:
      return "sheet_currency_title"
    case .language:
      return "sheet_language_title"
    }
  }
}

extension ChainSupportMode {
  var localizedDisplayName: LocalizedStringKey {
    switch self {
    case .limitedMainnet:
      return "preferences_network_mode_mainnet"
    case .limitedTestnet:
      return "preferences_network_mode_testnet"
    case .fullMainnet:
      return "preferences_network_mode_mainnet_plus"
    }
  }
}

extension AppAppearance {
  var localizedDisplayName: LocalizedStringKey {
    switch self {
    case .dark:
      return "preferences_appearance_dark"
    case .system:
      return "preferences_appearance_system"
    case .light:
      return "preferences_appearance_light"
    }
  }
}

struct PreferencesView: View {
  @Bindable var preferencesStore: PreferencesStore
  var onBack: () -> Void = {}
  @State private var activeModal: PreferencesModal?
  @State private var activePage: PreferencesPage = .main

  var body: some View {
    ZStack {
      AppThemeColor.backgroundPrimary.ignoresSafeArea()
      pageContent
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      AppHeader(
        title: activePage.title,
        titleFont: .custom("Roboto-Bold", size: 22),
        titleColor: AppThemeColor.labelSecondary,
        onBack: handleBack
      )
    }
    .sheet(item: $activeModal) { modal in
      AppSheet(kind: modal.sheetKind) {
        modalContent(for: modal)
      }
    }
  }

  @ViewBuilder
  private var pageContent: some View {
    switch activePage {
    case .main:
      List {
        Section {
          PreferenceRow(
            title: Text("preferences_appearance"),
            iconName: "moonphase.first.quarter",
            iconBackground: Color(hex: "#5E5CE6"),
            trailing: .localizedValueChevron(preferencesStore.appearance.localizedDisplayName),
            action: { present(.appearance) }
          )
          PreferenceRow(
            title: Text("preferences_haptics"),
            iconName: "iphone.radiowaves.left.and.right",
            iconBackground: Color(hex: "#FF9F0A"),
            trailing: .toggle(isOn: $preferencesStore.hapticsEnabled)
          )
          PreferenceRow(
            title: Text("preferences_network_mode"),
            iconName: "point.3.connected.trianglepath.dotted",
            iconBackground: Color(hex: "#0A84FF"),
            trailing: .custom(
              AnyView(NetworkModePullDown(mode: $preferencesStore.chainSupportMode))
            )
          )
          PreferenceRow(
            title: Text("preferences_currency"),
            iconName: "banknote",
            iconBackground: Color(hex: "#34C759"),
            trailing: .valueChevron(preferencesStore.selectedCurrencyCode.uppercased()),
            action: {
              withAnimation(.easeInOut(duration: 0.18)) {
                activePage = .currency
              }
            }
          )
          PreferenceRow(
            title: Text("preferences_language"),
            iconName: "globe",
            iconBackground: Color(hex: "#AF52DE"),
            trailing: .valueChevron(
              preferencesStore.selectedLanguage?.displayName ?? preferencesStore.languageCode
            ),
            action: {
              withAnimation(.easeInOut(duration: 0.18)) {
                activePage = .language
              }
            }
          )
        }
      }
      .listStyle(.insetGrouped)
      .scrollDisabled(true)
      .scrollContentBackground(.hidden)
      .scrollIndicators(.hidden)
    case .currency:
      CurrencySelectionPage(
        currencies: preferencesStore.supportedCurrencies,
        selectedCode: preferencesStore.selectedCurrencyCode,
        onSelect: { preferencesStore.selectedCurrencyCode = $0 }
      )
      .padding(.top, 16)
    case .language:
      LanguageSelectionPage(
        languages: preferencesStore.supportedLanguages,
        selectedCode: preferencesStore.languageCode,
        onSelect: { preferencesStore.languageCode = $0 }
      )
      .padding(.top, 16)
    }
  }

  @ViewBuilder
  private func modalContent(for modal: PreferencesModal) -> some View {
    switch modal {
    case .appearance:
      AppearancePickerModal(
        selectedAppearance: preferencesStore.appearance,
        onSelect: { appearance in
          preferencesStore.appearance = appearance
          dismissModal()
        }
      )
    }
  }

  private func present(_ modal: PreferencesModal) {
    activeModal = modal
  }

  private func handleBack() {
    if activePage == .main {
      onBack()
    } else {
      withAnimation(.easeInOut(duration: 0.18)) {
        activePage = .main
      }
    }
  }

  private func dismissModal() {
    activeModal = nil
  }
}

private struct NetworkModePullDown: View {
  @Binding var mode: ChainSupportMode

  var body: some View {
    Picker(selection: $mode) {
      Text("preferences_network_mode_mainnet")
        .tag(ChainSupportMode.limitedMainnet)
      Text("preferences_network_mode_testnet")
        .tag(ChainSupportMode.limitedTestnet)
    } label: {
    }
    .pickerStyle(.menu)
    .tint(AppThemeColor.labelSecondary)
    .accentColor(AppThemeColor.labelSecondary)
    .foregroundStyle(AppThemeColor.labelSecondary)
    .buttonStyle(.plain)
  }
}

private struct PreferenceRow: View {
  enum Trailing {
    case chevron
    case toggle(isOn: Binding<Bool>)
    case valueChevron(String)
    case localizedValueChevron(LocalizedStringKey)
    case custom(AnyView)
  }

  let title: Text
  let iconName: String
  let iconBackground: Color
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
      HStack(spacing: 12) {
        IconBadge(
          style: .solid(
            background: iconBackground,
            icon: AppThemeColor.grayWhite
          ),
          contentPadding: 6,
          cornerRadius: 9,
          borderWidth: 0
        ) {
          Image(systemName: iconName)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 14, height: 14)
        }

        title
          .font(.custom("Roboto-Medium", size: 15))
          .foregroundStyle(AppThemeColor.labelPrimary)
      }

      Spacer(minLength: 0)

      switch trailing {
      case .chevron:
        Chevron()
      case .toggle(let isOn):
        ToggleSwitch(isOn: isOn)
      case .valueChevron(let value):
        HStack(spacing: 10) {
          Text(value)
            .font(.custom("Roboto-Regular", size: 15))
            .foregroundStyle(AppThemeColor.labelSecondary)
          Chevron()
        }
      case .localizedValueChevron(let value):
        HStack(spacing: 10) {
          Text(value)
            .font(.custom("Roboto-Regular", size: 15))
            .foregroundStyle(AppThemeColor.labelSecondary)
          Chevron()
        }
      case .custom(let view):
        view
      }
    }
    .frame(maxWidth: .infinity)
  }
}

private struct Chevron: View {
  var body: some View {
    Image(systemName: "chevron.right")
      .font(.system(size: 12, weight: .semibold))
      .frame(width: 12, height: 12)
      .foregroundStyle(AppThemeColor.glyphSecondary)
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
            Text(appearance.localizedDisplayName)
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
      HStack(spacing: 0) {
        AppThemeColor.grayBlack
        AppThemeColor.grayWhite
      }
    case .light:
      AppThemeColor.grayWhite
    }
  }
}

#Preview {
  PreferencesView(preferencesStore: PreferencesStore())
}

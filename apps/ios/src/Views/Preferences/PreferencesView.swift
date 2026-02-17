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
  @State private var selectionTrigger = 0

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
    .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: selectionTrigger) { _, _ in
      preferencesStore.hapticsEnabled
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
            action: { selectionTrigger += 1; present(.appearance) }
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
              selectionTrigger += 1
              withAnimation(AppAnimation.standard) {
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
              selectionTrigger += 1
              withAnimation(AppAnimation.standard) {
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
      .padding(.top, AppSpacing.md)
    case .language:
      LanguageSelectionPage(
        languages: preferencesStore.supportedLanguages,
        selectedCode: preferencesStore.languageCode,
        onSelect: { preferencesStore.languageCode = $0 }
      )
      .padding(.top, AppSpacing.md)
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
      withAnimation(AppAnimation.standard) {
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
      HStack(spacing: AppSpacing.sm) {
        IconBadge(
          style: .solid(
            background: iconBackground,
            icon: AppThemeColor.grayWhite
          ),
          contentPadding: 6,
          cornerRadius: AppCornerRadius.sm,
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
        ChevronIcon()
      case .toggle(let isOn):
        ToggleSwitch(isOn: isOn)
      case .valueChevron(let value):
        HStack(spacing: 10) {
          Text(value)
            .font(.custom("Roboto-Regular", size: 15))
            .foregroundStyle(AppThemeColor.labelSecondary)
          ChevronIcon()
        }
      case .localizedValueChevron(let value):
        HStack(spacing: 10) {
          Text(value)
            .font(.custom("Roboto-Regular", size: 15))
            .foregroundStyle(AppThemeColor.labelSecondary)
          ChevronIcon()
        }
      case .custom(let view):
        view
      }
    }
    .frame(maxWidth: .infinity)
  }
}

#Preview {
  PreferencesView(preferencesStore: PreferencesStore())
}

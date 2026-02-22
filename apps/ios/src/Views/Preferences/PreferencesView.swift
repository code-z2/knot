import Observation
import SwiftUI

struct PreferencesView: View {
    @Bindable var preferencesStore: PreferencesStore
    var onBack: () -> Void = {}
    @State var activeModal: PreferencesModalModel?
    @State var activePage: PreferencesPageModel = .main
    @State var selectionTrigger = 0

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
                onBack: handleBack,
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
    var pageContent: some View {
        switch activePage {
        case .main:
            List {
                Section {
                    PreferenceRow(
                        title: Text("preferences_appearance"),
                        iconName: "moonphase.first.quarter",
                        iconBackground: Color(hex: "#5E5CE6"),
                        trailing: .localizedValueChevron(preferencesStore.appearance.localizedDisplayName),
                        action: {
                            selectionTrigger += 1
                            present(.appearance)
                        },
                    )
                    PreferenceRow(
                        title: Text("preferences_haptics"),
                        iconName: "iphone.radiowaves.left.and.right",
                        iconBackground: Color(hex: "#FF9F0A"),
                        trailing: .toggle(isOn: $preferencesStore.hapticsEnabled),
                    )
                    PreferenceRow(
                        title: Text("preferences_network_mode"),
                        iconName: "point.3.connected.trianglepath.dotted",
                        iconBackground: Color(hex: "#0A84FF"),
                        trailing: .custom(AnyView(NetworkModePullDown(mode: $preferencesStore.chainSupportMode))),
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
                        },
                    )
                    PreferenceRow(
                        title: Text("preferences_language"),
                        iconName: "globe",
                        iconBackground: Color(hex: "#AF52DE"),
                        trailing: .valueChevron(
                            preferencesStore.selectedLanguage?.displayName ?? preferencesStore.languageCode,
                        ),
                        action: {
                            selectionTrigger += 1
                            withAnimation(AppAnimation.standard) {
                                activePage = .language
                            }
                        },
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
                onSelect: { preferencesStore.selectedCurrencyCode = $0 },
            )
            .padding(.top, AppSpacing.md)
            .transition(AppAnimation.slideTransition)
        case .language:
            LanguageSelectionPage(
                languages: preferencesStore.supportedLanguages,
                selectedCode: preferencesStore.languageCode,
                onSelect: { preferencesStore.languageCode = $0 },
            )
            .padding(.top, AppSpacing.md)
            .transition(AppAnimation.slideTransition)
        }
    }
}

#Preview {
    PreferencesView(preferencesStore: PreferencesStore())
}

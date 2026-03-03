// PreferencesView.swift
// Created by Peter Anyaogu on 03/03/2026.

import Observation
import SwiftUI

struct PreferencesView: View {
    @Bindable var preferencesStore: PreferencesStore

    @Environment(\.dismiss)
    var dismiss

    @State var activeModal: PreferencesModalModel?

    @State var selectionTrigger = 0

    var body: some View {
        ZStack {
            AppBackgroundView()
            pageContent
        }
        .appNavigation(
            titleKey: "preferences_title",
            displayMode: .inline,
            hidesBackButton: false,
        )
        .sheet(item: $activeModal) { modal in
            AppSheet(kind: modal.sheetKind) {
                modalContent(for: modal)
            }
        }
        .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: selectionTrigger) { _, _ in
            preferencesStore.hapticsEnabled
        }
    }

    var pageContent: some View {
        List {
            Section {
                PreferenceRow(
                    title: Text("preferences_appearance"),
                    iconName: "moonphase.first.quarter",
                    iconBackground: Color(hex: "#5E5CE6"),
                    trailing: PreferenceRow.Trailing.localizedValueChevron(
                        preferencesStore.appearance.localizedDisplayName,
                    ),
                    action: {
                        selectionTrigger += 1
                        present(.appearance)
                    },
                )
                PreferenceRow(
                    title: Text("preferences_haptics"),
                    iconName: "iphone.radiowaves.left.and.right",
                    iconBackground: Color(hex: "#FF9F0A"),
                    trailing: .toggle(isOn: Binding(
                        get: { preferencesStore.hapticsEnabled },
                        set: { preferencesStore.setHapticsEnabled($0) },
                    )),
                )
                PreferenceRow(
                    title: Text("preferences_network_mode"),
                    iconName: "point.3.connected.trianglepath.dotted",
                    iconBackground: Color(hex: "#0A84FF"),
                    trailing: .custom(AnyView(NetworkModePullDown(mode: Binding(
                        get: { preferencesStore.chainSupportMode },
                        set: { preferencesStore.selectChainSupportMode($0) },
                    )))),
                )
                NavigationLink {
                    CurrencySelectionPage(
                        currencies: preferencesStore.supportedCurrencies,
                        selectedCode: preferencesStore.selectedCurrencyCode,
                        onSelect: { preferencesStore.selectCurrency($0) },
                    )
                    .appNavigation(
                        titleKey: "sheet_currency_title",
                        displayMode: .inline,
                        hidesBackButton: false,
                    )
                    .appNavigationScrollEdgeStyle()
                } label: {
                    PreferenceRow(
                        title: Text("preferences_currency"),
                        iconName: "banknote",
                        iconBackground: Color(hex: "#34C759"),
                        trailing: .custom(
                            AnyView(
                                Text(preferencesStore.selectedCurrencyCode.uppercased())
                                    .font(AppTypography.bodyRegular)
                                    .foregroundStyle(AppThemeColor.labelSecondary),
                            ),
                        ),
                    )
                }
                .contentShape(Rectangle())

                NavigationLink {
                    LanguageSelectionPage(
                        languages: preferencesStore.supportedLanguages,
                        selectedCode: preferencesStore.languageCode,
                        onSelect: { preferencesStore.selectLanguage($0) },
                    )
                    .appNavigation(
                        titleKey: "sheet_language_title",
                        displayMode: .inline,
                        hidesBackButton: false,
                    )
                    .appNavigationScrollEdgeStyle()
                } label: {
                    PreferenceRow(
                        title: Text("preferences_language"),
                        iconName: "globe",
                        iconBackground: Color(hex: "#AF52DE"),
                        trailing: .custom(
                            AnyView(
                                Text(
                                    preferencesStore.selectedLanguage?.displayName
                                        ?? preferencesStore.languageCode,
                                )
                                .font(AppTypography.bodyRegular)
                                .foregroundStyle(AppThemeColor.labelSecondary),
                            ),
                        ),
                    )
                }
                .contentShape(Rectangle())
            }
        }
        .listStyle(.insetGrouped)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }
}

#Preview {
    NavigationStack {
        PreferencesView(preferencesStore: PreferencesStore())
    }
}

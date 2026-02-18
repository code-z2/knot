import SwiftUI

struct LanguageSelectionPage: View {
    let languages: [LanguageOption]
    let selectedCode: String
    let onSelect: (String) -> Void
    @State private var selectionTrigger = 0

    private var currentLayoutDirection: LayoutDirection {
        Locale.Language(identifier: selectedCode).characterDirection == .rightToLeft
            ? .rightToLeft
            : .leftToRight
    }

    var body: some View {
        List {
            Section {
                ForEach(languages) { language in
                    LanguageSelectionRow(
                        title: Text(language.displayName),
                        isSelected: language.code == selectedCode,
                        onTap: { selectionTrigger += 1; onSelect(language.code) },
                    ) {
                        Text(language.flag)
                            .font(.custom("Inter-Regular", size: 15))
                    }
                }
            }
        }
        .id(currentLayoutDirection)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.layoutDirection, currentLayoutDirection)
        .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: selectionTrigger) { _, _ in true }
    }
}

private struct LanguageSelectionRow<Leading: View>: View {
    let title: Text
    let isSelected: Bool
    let onTap: () -> Void
    let leading: () -> Leading

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppSpacing.md) {
                leading()

                title
                    .font(.custom("Roboto-Medium", size: 15))
                    .foregroundStyle(AppThemeColor.labelPrimary)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppThemeColor.accentBrown)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Language Selection") {
    ZStack {
        AppThemeColor.backgroundPrimary.ignoresSafeArea()
        LanguageSelectionPage(
            languages: PreferencesStore.defaultLanguages,
            selectedCode: "en",
            onSelect: { _ in },
        )
        .padding(.top, AppHeaderMetrics.contentTopPadding)
    }
}

import SwiftUI

struct LanguageSelectionPage: View {
    let languages: [LanguageOption]
    let selectedCode: String
    let onSelect: (String) -> Void
    @State private var selectionTrigger = 0
    @State private var query = ""

    var body: some View {
        List {
            ForEach(filteredLanguages) { language in
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
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(AppThemeColor.backgroundPrimary)
        .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: selectionTrigger) { _, _ in true }
        .searchable(text: $query, placement: .toolbar, prompt: Text("search_placeholder"))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
    }

    private var filteredLanguages: [LanguageOption] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return languages }
        return languages.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
                || $0.code.localizedCaseInsensitiveContains(trimmed)
        }
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
    }
}

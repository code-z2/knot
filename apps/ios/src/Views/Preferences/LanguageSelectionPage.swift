import SwiftUI

struct LanguageSelectionPage: View {
  let languages: [LanguageOption]
  let selectedCode: String
  let onSelect: (String) -> Void

  var body: some View {
    List {
      Section {
        ForEach(languages) { language in
          LanguageSelectionRow(
            title: Text(language.displayName),
            isSelected: language.code == selectedCode,
            onTap: { onSelect(language.code) }
          ) {
            Text(language.flag)
              .font(.custom("Inter-Regular", size: 15))
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .scrollIndicators(.hidden)
  }
}

private struct LanguageSelectionRow<Leading: View>: View {
  let title: Text
  let isSelected: Bool
  let onTap: () -> Void
  let leading: () -> Leading

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 16) {
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
      onSelect: { _ in }
    )
    .padding(.top, AppHeaderMetrics.contentTopPadding)
  }
}

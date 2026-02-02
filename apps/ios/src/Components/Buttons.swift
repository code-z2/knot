import SwiftUI

struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.button)
                .foregroundStyle(AppThemeColor.backgroundPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(AppThemeColor.accentBrown, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct TextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTypography.button)
                .foregroundStyle(AppThemeColor.fixedDarkText)
                .padding(.horizontal, 21)
                .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}

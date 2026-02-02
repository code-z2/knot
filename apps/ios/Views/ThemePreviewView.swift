import SwiftUI

struct ThemePreviewView: View {
    var body: some View {
        ZStack {
            AppThemeColor.backgroundPrimary.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("Metu")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(AppThemeColor.labelPrimary)

                Text("Dark-first theme initialized from Figma tokens")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppThemeColor.labelSecondary)

                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppThemeColor.accentBrown)
                        .frame(width: 56, height: 36)

                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppThemeColor.destructiveBackground)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppThemeColor.accentRed, lineWidth: 1)
                        }
                        .frame(width: 56, height: 36)

                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppThemeColor.fillSecondary)
                        .frame(width: 56, height: 36)
                }

                Divider()
                    .overlay(AppThemeColor.separatorOpaque)
            }
            .padding(24)
            .background(AppThemeColor.grayBlack.opacity(0.2), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(AppThemeColor.separatorNonOpaque, lineWidth: 1)
            }
            .padding(24)
        }
    }
}

#Preview {
    ThemePreviewView()
        .preferredColorScheme(.dark)
}

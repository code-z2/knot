import SwiftUI

struct WalletBackupPhraseCard: View {
    let mnemonic: String
    @Binding var isMnemonicRevealed: Bool
    let onRevealTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("wallet_backup_secret_phrase")
                .font(.custom("Roboto-Regular", size: 14))
                .foregroundStyle(AppThemeColor.labelSecondary)
                .padding(.horizontal, 10)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppThemeColor.backgroundSecondary)
                    .frame(height: 154)

                Text(mnemonic)
                    .font(.custom("RobotoMono-Regular", size: 14))
                    .foregroundStyle(AppThemeColor.labelPrimary)
                    .padding(.horizontal, 18)
                    .padding(.top, AppSpacing.md)
                    .multilineTextAlignment(.leading)
                    .blur(radius: isMnemonicRevealed ? 0 : 6)

                if !isMnemonicRevealed {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .glassEffect(.clear.interactive(), in: .rect)
                        .clipShape(.rect(cornerRadius: 16))
                        .frame(height: 154)
                        .overlay {
                            Button(action: onRevealTap) {
                                Text("wallet_backup_tap_to_reveal")
                                    .font(.custom("Roboto-Medium", size: 14))
                                    .foregroundStyle(AppThemeColor.labelSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, AppSpacing.xs)
                            }
                            .buttonStyle(.plain)
                        }
                }
            }
            .frame(width: 351)
        }
    }
}

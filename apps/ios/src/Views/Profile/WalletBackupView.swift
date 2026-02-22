import SwiftUI

struct WalletBackupView: View {
    let mnemonic: String
    var onBack: () -> Void = {}
    @State var isMnemonicRevealed = false
    @State var didCopy = false
    @State var copyResetTask: Task<Void, Never>?
    @State var revealTrigger = 0
    @State var copyTrigger = 0

    var body: some View {
        ZStack {
            AppThemeColor.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 36) {
                VStack(alignment: .leading, spacing: 53) {
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                        Text("wallet_backup_instructions")
                            .font(.custom("RobotoMono-Medium", size: 16))
                            .foregroundStyle(AppThemeColor.labelPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    WalletBackupPhraseCard(
                        mnemonic: mnemonic,
                        isMnemonicRevealed: $isMnemonicRevealed,
                        onRevealTap: handleRevealTap,
                    )
                }

                Button {
                    handleCopyTap()
                } label: {
                    HStack(spacing: 10) {
                        Text(copyButtonTitle)
                            .font(.custom("Roboto-Bold", size: 15))
                            .foregroundStyle(AppThemeColor.accentBrown)
                            .contentTransition(.numericText())

                        if !didCopy {
                            Image(systemName: "square.on.square")
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 16, height: 16)
                                .foregroundStyle(AppThemeColor.accentBrown)
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        }
                    }
                    .animation(AppAnimation.standard, value: didCopy)
                    .padding(.horizontal, 21)
                    .padding(.vertical, 13)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppHeaderMetrics.contentTopPadding)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            AppHeader(
                title: "wallet_backup_title",
                titleFont: .custom("Roboto-Bold", size: 22),
                titleColor: AppThemeColor.labelSecondary,
                onBack: onBack,
            )
        }
        .onDisappear {
            copyResetTask?.cancel()
            copyResetTask = nil
        }
        .sensoryFeedback(AppHaptic.lightImpact.sensoryFeedback, trigger: revealTrigger) { _, _ in true }
        .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: copyTrigger) { _, _ in true }
    }

    private var copyButtonTitle: LocalizedStringKey {
        didCopy ? "receive_copied" : "wallet_backup_copy"
    }
}

#Preview {
    WalletBackupView(
        mnemonic: "a brown fox jumped over a lazy dog and broke a leg",
    )
}

import SwiftUI
import UIKit

struct WalletBackupView: View {
  let mnemonic: String
  var onBack: () -> Void = {}
  @State private var isMnemonicRevealed = false
  @State private var didCopy = false
  @State private var copyResetTask: Task<Void, Never>?
  @State private var revealTrigger = 0
  @State private var copyTrigger = 0

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
                   .glassEffect(.clear.interactive(), in:  .rect)
                   .clipShape(.rect(cornerRadius: 16))
                   .frame(height: 154)
                  .overlay {
                    Button {
                      revealTrigger += 1
                      withAnimation(AppAnimation.gentle) {
                        isMnemonicRevealed = true
                      }
                    } label: {
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

        Button {
          copyTrigger += 1
          UIPasteboard.general.string = mnemonic
          didCopy = true
          copyResetTask?.cancel()
          copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            didCopy = false
          }
        } label: {
          HStack(spacing: 10) {
            Text(didCopy ? "receive_copied" : "wallet_backup_copy")
              .font(.custom("Roboto-Bold", size: 15))
              .foregroundStyle(AppThemeColor.accentBrown)

            if !didCopy {
              Image(systemName: "square.on.square")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 16, height: 16)
                .foregroundStyle(AppThemeColor.accentBrown)
            }

          }
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
        onBack: onBack
      )
    }
    .onDisappear {
      copyResetTask?.cancel()
      copyResetTask = nil
    }
    .sensoryFeedback(AppHaptic.lightImpact.sensoryFeedback, trigger: revealTrigger) { _, _ in true }
    .sensoryFeedback(AppHaptic.selection.sensoryFeedback, trigger: copyTrigger) { _, _ in true }
  }
}

#Preview {
  WalletBackupView(
    mnemonic: "a brown fox jumped over a lazy dog and broke a leg"
  )
}

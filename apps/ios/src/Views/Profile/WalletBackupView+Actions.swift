import SwiftUI
import UIKit

extension WalletBackupView {
    func handleRevealTap() {
        revealTrigger += 1
        withAnimation(AppAnimation.gentle) {
            isMnemonicRevealed = true
        }
    }

    func handleCopyTap() {
        copyTrigger += 1
        UIPasteboard.general.string = mnemonic
        didCopy = true
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.1))
            didCopy = false
        }
    }
}

import Balance
import SwiftUI

extension HomeView {
    func handleAddMoneyTap() {
        lightImpactTrigger += 1
        onAddMoney()
    }

    func handleSendMoneyTap() {
        lightImpactTrigger += 1
        onSendMoney()
    }

    func handleProfileTap() {
        selectionTrigger += 1
        onProfileTap()
    }

    func handlePreferencesTap() {
        selectionTrigger += 1
        onPreferencesTap()
    }

    func handleWalletBackupTap() {
        selectionTrigger += 1
        onWalletBackupTap()
    }

    func handleAddressBookTap() {
        selectionTrigger += 1
        onAddressBookTap()
    }

    func presentAssetsModal() {
        selectionTrigger += 1
        activeModal = .assets
    }

    func refreshBalances() async {
        refreshTrigger += 1
        await onRefreshWallet()
    }

    func beginLogout() {
        guard !isLoggingOut else { return }
        warningTrigger += 1
        withAnimation(AppAnimation.standard) {
            isLoggingOut = true
        }
        logoutTask?.cancel()
        logoutTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.5))
            } catch {
                isLoggingOut = false
                return
            }
            onSignOut()
        }
    }
}

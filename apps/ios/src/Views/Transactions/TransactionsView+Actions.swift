import SwiftUI
import Transactions

extension TransactionsView {
    func presentReceipt(for transaction: TransactionRecordModel) {
        selectionTrigger += 1
        selectedTransaction = transaction
    }

    func dismissReceipt() {
        selectedTransaction = nil
    }

    func openExplorer(_ url: URL) {
        dismissReceipt()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            openURL(url, prefersInApp: true)
        }
    }
}

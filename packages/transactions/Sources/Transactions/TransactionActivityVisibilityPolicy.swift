import Foundation

struct TransactionActivityVisibilityPolicy {
    func shouldInclude(
        item: ZerionTransactionItem,
        record: TransactionRecordModel,
        ownedAddresses: Set<String>,
        accumulatorAddress: String?,
    ) -> Bool {
        let from = record.fromAddress.lowercased()
        let to = record.toAddress.lowercased()
        let operationType = (item.attributes.operationType ?? "").lowercased()

        if !from.isEmpty, !to.isEmpty, ownedAddresses.contains(from), ownedAddresses.contains(to) {
            return false
        }

        if let accumulatorAddress,
           to == accumulatorAddress,
           !from.isEmpty,
           !ownedAddresses.contains(from),
           ["receive", "deposit", "bridge", "trade", "execute"].contains(operationType)
        {
            return false
        }

        let hasVisibleAssetValue = record.valueQuoteUSD > 0
            || !record.assetAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if record.variant == .contract, !hasVisibleAssetValue {
            return false
        }

        return true
    }
}

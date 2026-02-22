import Foundation

struct ExecuteXInitializationPolicy {
    func accumulatorOnlyChainsInOrder(leaves: [ExecuteXLeafRequest]) -> [UInt64] {
        let executeLeafChains = Set(
            leaves.compactMap { leaf -> UInt64? in
                if case .executeCalls = leaf.payload {
                    return leaf.chainId
                }
                return nil
            },
        )

        var chainOrder: [UInt64] = []
        var seenChains = Set<UInt64>()
        for leaf in leaves {
            guard case .accumulatorIntent = leaf.payload else { continue }
            guard !executeLeafChains.contains(leaf.chainId) else { continue }
            if seenChains.insert(leaf.chainId).inserted {
                chainOrder.append(leaf.chainId)
            }
        }
        return chainOrder
    }
}
